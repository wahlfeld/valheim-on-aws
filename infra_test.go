package test

import (
	"crypto/tls"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	taws "github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

var uniqueID string = strings.ToLower(random.UniqueId())
var stateBucket string = fmt.Sprintf("%s-terratest-valheim", uniqueID)
var key string = fmt.Sprintf("%s/terraform.tfstate", uniqueID)
var worldName string = "test-world"
var l *logger.Logger

func TestTerraform(t *testing.T) {
	t.Parallel()

	workingDir := "./template"
	region := taws.GetRandomStableRegion(t, nil, nil)

	defer test_structure.RunTestStage(t, "teardown_state_bucket", func() {
		cleanUpStateBucket(t, region, stateBucket)
	})

	defer test_structure.RunTestStage(t, "teardown_terraform", func() {
		undeployUsingTerraform(t, workingDir)
	})

	defer test_structure.RunTestStage(t, "logs", func() {
		fetchSyslogForInstance(t, region, workingDir)
	})

	test_structure.RunTestStage(t, "create_state_bucket", func() {
		taws.CreateS3Bucket(t, region, stateBucket)
	})

	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, region, workingDir)
	})

	test_structure.RunTestStage(t, "check_state_bucket", func() {
		contents := taws.GetS3ObjectContents(t, region, stateBucket, key)
		require.Contains(t, contents, uniqueID)
	})

	test_structure.RunTestStage(t, "check_s3_bucket_config", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		actualStatus := taws.GetS3BucketVersioning(t, region, bucketID)
		expectedStatus := "Enabled"
		assert.Equal(t, expectedStatus, actualStatus)

		taws.AssertS3BucketPolicyExists(t, region, bucketID)
	})

	test_structure.RunTestStage(t, "test_instance_ssm", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		timeout := 3 * time.Minute

		taws.WaitForSsmInstance(t, region, instanceID, timeout)

		result := taws.CheckSsmCommand(t, region, instanceID, "echo Hello, World", timeout)
		require.Equal(t, result.Stdout, "Hello, World\n")
		require.Equal(t, result.Stderr, "")
		require.Equal(t, int64(0), result.ExitCode)

		result, err := taws.CheckSsmCommandE(t, region, instanceID, "cat /wrong/file", timeout)
		require.Error(t, err)
		require.Equal(t, "Failed", err.Error())
		require.Equal(t, "cat: /wrong/file: No such file or directory\nfailed to run commands: exit status 1", result.Stderr)
		require.Equal(t, "", result.Stdout)
		require.Equal(t, int64(1), result.ExitCode)
	})

	test_structure.RunTestStage(t, "check_monitoring", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		monitoringURL := terraform.Output(t, terraformOptions, "monitoring_url")

		validateResponse(t, monitoringURL, 25, 5*time.Second)
	})

	test_structure.RunTestStage(t, "check_valheim_service", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		timeout := 3 * time.Minute

		taws.WaitForSsmInstance(t, region, instanceID, timeout)

		retry.DoWithRetry(t, "Checking if Valheim service is running", 55, 5*time.Second, func() (string, error) {
			out, _ := taws.CheckSsmCommandE(t, region, instanceID, "systemctl is-active valheim", timeout)

			expectedStatus := "active"
			actualStatus := strings.TrimSpace(out.Stdout)

			if actualStatus != expectedStatus {
				return "", fmt.Errorf("Expected status to be '%s' but was '%s'", expectedStatus, actualStatus)
			}

			return "", nil
		})
	})

	test_structure.RunTestStage(t, "test_create_backup", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		bucketID := terraform.Output(t, terraformOptions, "bucket_id")
		instanceID := terraform.Output(t, terraformOptions, "instance_id")

		sess := session.Must(session.NewSession(&aws.Config{
			Region: aws.String(region),
		}))

		svc := ec2.New(sess)
		inputStop := &ec2.StopInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		}
		_, err := svc.StopInstances(inputStop)
		if err != nil {
			t.Fatal(err)
		}

		err = svc.WaitUntilInstanceStopped(&ec2.DescribeInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		})
		if err != nil {
			t.Fatal(err)
		}

		fileNames := []string{worldName + ".fwl", worldName + ".db"}
		checkS3FilesExist(t, sess, bucketID, fileNames)

		inputStart := &ec2.StartInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		}
		_, err = svc.StartInstances(inputStart)
		if err != nil {
			t.Fatal(err)
		}

		err = svc.WaitUntilInstanceRunning(&ec2.DescribeInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		})
		if err != nil {
			t.Fatal(err)
		}
	})

	test_structure.RunTestStage(t, "test_restore_backup", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")

		logs := taws.GetSyslogForInstance(t, instanceID, region)

		if !strings.Contains(logs, "Backups found, restoring...") {
			t.Fatalf("Expected log message 'Backups found, restoring...' not found in syslog")
		}
	})
}

func deployUsingTerraform(t *testing.T, region string, workingDir string) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: workingDir,
		Vars: map[string]interface{}{
			"aws_region":      region,
			"instance_type":   "t3.medium",
			"purpose":         "test",
			"server_name":     "test-server",
			"server_password": "test-password",
			"sns_email":       "fake@email.com",
			"unique_id":       uniqueID,
			"world_name":      worldName,
			"admins": map[string]interface{}{
				fmt.Sprintf("%s-testuser1", uniqueID): 76561197993928956,
				fmt.Sprintf("%s-testuser2", uniqueID): 76561197994340320,
				fmt.Sprintf("%s-testuser3", uniqueID): "",
			},
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION":  region,
			"AWS_SDK_LOAD_CONFIG": "true",
		},
		BackendConfig: map[string]interface{}{
			"bucket": stateBucket,
			"key":    key,
			"region": region,
		},
	})

	test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)
}

func undeployUsingTerraform(t *testing.T, workingDir string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	terraform.Destroy(t, terraformOptions)
}

func cleanUpStateBucket(t *testing.T, region string, stateBucket string) {
	taws.EmptyS3Bucket(t, region, stateBucket)
	taws.DeleteS3Bucket(t, region, stateBucket)
}

func validateResponse(t *testing.T, address string, maxRetries int, timeBetweenRetries time.Duration) {
	http_helper.HttpGetWithRetryWithCustomValidation(t, address, &tls.Config{InsecureSkipVerify: true}, maxRetries, timeBetweenRetries, func(status int, body string) bool {
		return status == http.StatusOK
	})
}

func fetchSyslogForInstance(t *testing.T, region string, workingDir string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

	instanceID := terraform.OutputRequired(t, terraformOptions, "instance_id")
	logs := taws.GetSyslogForInstance(t, instanceID, region)

	l.Logf(t, "Most recent syslog for Instance %s:\n\n%s\n", instanceID, logs)
}

func checkS3FilesExist(t *testing.T, sess *session.Session, bucketName string, fileNames []string) {
	svc := s3.New(sess)

	for _, fileName := range fileNames {
		input := &s3.HeadObjectInput{
			Bucket: aws.String(bucketName),
			Key:    aws.String(fileName),
		}

		_, err := svc.HeadObject(input)
		if err != nil {
			if awsErr, ok := err.(awserr.Error); ok && awsErr.Code() == "NotFound" {
				t.Fatalf("File %s does not exist in the bucket %s", fileName, bucketName)
			}
			t.Fatal(err)
		}
	}
}
