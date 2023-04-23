package test

import (
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
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

	defer test_structure.RunTestStage(t, "teardown_terraform_and_state_bucket", func() {
		_, err := undeployUsingTerraform(t, workingDir)
		if err != nil {
			log.Fatal("Terraform destroy failed, skipping state bucket teardown. Manual intervention required.")
			t.SkipNow()
		}
		emptyAndDeleteBucket(t, region, stateBucket)
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

		err := checkValheimIsRunning(t, region, instanceID)
		if err != nil {
			log.Printf("Valheim is not running on instance %s", instanceID)
			t.Fatal(err)
		}
	})

	test_structure.RunTestStage(t, "test_backup", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		sess := session.Must(session.NewSession(&aws.Config{
			Region: aws.String(region),
		}))

		err := startStopInstance(sess, instanceID)
		if err != nil {
			log.Printf("Error start stopping instance %s", instanceID)
			t.Fatal(err)
		}

		log.Printf("Checking that world files exist in S3 bucket %s", bucketID)
		fileNames := []string{worldName + ".fwl", worldName + ".db"}
		err = checkFilesExistInBucket(t, sess, bucketID, fileNames)
		if err != nil {
			log.Print("Files not found in bucket")
			t.Fatal(err)
		}
		log.Print("Files found in bucket!")
	})

	test_structure.RunTestStage(t, "test_restore", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		bucketID := terraform.Output(t, terraformOptions, "bucket_id")
		defer emptyAndDeleteBucket(t, region, bucketID)

		err := checkValheimIsRunning(t, region, instanceID)
		if err != nil {
			log.Printf("Valheim is not running on instance %s", instanceID)
			t.Fatal(err)
		}

		timeout := 3 * time.Minute
		taws.WaitForSsmInstance(t, region, instanceID, timeout)

		log.Print("Removing local world files if they exist")
		rmCmd1 := fmt.Sprintf("rm -rf /home/vhserver/.config/unity3d/IronGate/Valheim/worlds_local/%s.fwl", worldName)
		rmCmd2 := fmt.Sprintf("rm -rf /home/vhserver/.config/unity3d/IronGate/Valheim/worlds_local/%s.db", worldName)

		_, err = taws.CheckSsmCommandE(t, region, instanceID, rmCmd1, 5*time.Second)
		if err != nil {
			t.Fatalf("Failed to run command %s", rmCmd1)
		}
		_, err = taws.CheckSsmCommandE(t, region, instanceID, rmCmd2, 5*time.Second)
		if err != nil {
			t.Fatalf("Failed to run command %s", rmCmd2)
		}

		log.Print("Restarting Valheim service")
		systemctlCmd := "systemctl restart valheim.service"
		_, err = taws.CheckSsmCommandE(t, region, instanceID, systemctlCmd, 150*time.Second)
		if err != nil {
			t.Fatalf("Failed to run command %s", systemctlCmd)
		}

		logCmd := "grep 'Backups found, restoring...' /var/log/syslog"

		retry.DoWithRetry(t, "Checking if backups were restored from S3", 60, 5*time.Second, func() (string, error) {
			out, err := taws.CheckSsmCommandE(t, region, instanceID, logCmd, timeout)
			if err != nil {
				return "", fmt.Errorf("Error running command: %v", err)
			}

			log.Print("Checking if log was found")
			if out == nil {
				return "", fmt.Errorf("Log not found (was nil)")
			}
			if out.Stdout == "" {
				return "", fmt.Errorf("Log not found (was \"\")")
			}

			log.Print("Log found!")
			return "", nil
		})

		log.Print("############")
		log.Print("### PASS ###")
		log.Print("############")
		log.Printf("Emptying and deleting bucket %s now, so that Terraform can destroy it", bucketID)
		log.Print("Skipping syslog...")
		os.Setenv("SKIP_logs", "true")
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

func undeployUsingTerraform(t *testing.T, workingDir string) (string, error) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	out, err := terraform.DestroyE(t, terraformOptions)
	if err != nil {
		return out, err
	}
	return out, nil
}

func emptyAndDeleteBucket(t *testing.T, region string, bucket string) {
	taws.EmptyS3Bucket(t, region, bucket)
	taws.DeleteS3Bucket(t, region, bucket)
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

func checkFilesExistInBucket(t *testing.T, sess *session.Session, bucketName string, fileNames []string) error {
	svc := s3.New(sess)

	for _, fileName := range fileNames {
		input := &s3.HeadObjectInput{
			Bucket: aws.String(bucketName),
			Key:    aws.String(fileName),
		}

		_, err := svc.HeadObject(input)
		if err != nil {
			if awsErr, ok := err.(awserr.Error); ok && awsErr.Code() == "NotFound" {
				return fmt.Errorf("File %s does not exist in the bucket %s", fileName, bucketName)
			}
			return err
		}
	}
	return nil
}

func startStopInstance(sess *session.Session, instanceID string) error {
	svc := ec2.New(sess)

	log.Printf("Stopping instance %s", instanceID)
	inputStop := &ec2.StopInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	}
	_, err := svc.StopInstances(inputStop)
	if err != nil {
		return err
	}

	log.Printf("Waiting until instance %s has stopped", instanceID)
	err = svc.WaitUntilInstanceStopped(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	if err != nil {
		return err
	}

	startTime := time.Now()
	attempts := 0
	readyToStart := false

	for !readyToStart {
		if time.Since(startTime) > 5*time.Minute {
			log.Printf("Timed out waiting for instance %s to be ready to start", instanceID)
			return err
		}
		attempts++
		log.Printf("Starting instance %s (attempt %d)", instanceID, attempts)

		inputStart := &ec2.StartInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		}
		_, err := svc.StartInstances(inputStart)
		if err == nil {
			readyToStart = true
		} else {
			log.Printf("Error starting instance %s: %s", instanceID, err.Error())
			log.Print("Instance not ready to start. Sleeping for 5s and will try again.")
			time.Sleep(5 * time.Second)
		}
	}

	log.Printf("Instance %s was ready to start after %d attempts", instanceID, attempts)

	log.Printf("Waiting until instance %s is running", instanceID)
	err = svc.WaitUntilInstanceRunning(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	if err != nil {
		return err
	}

	return nil
}

func checkValheimIsRunning(t *testing.T, region string, instanceID string) error {
	_, err := retry.DoWithRetryE(t, "Checking if Valheim service is active", 60, 5*time.Second, func() (string, error) {
		out, err := taws.CheckSsmCommandE(t, region, instanceID, "systemctl is-active valheim", 3*time.Minute)
		if err != nil {
			return "", fmt.Errorf("Failed to run command")
		}

		expectedStatus := "active"
		actualStatus := strings.TrimSpace(out.Stdout)

		if actualStatus != expectedStatus {
			return "", fmt.Errorf("Expected status to be '%s' but was '%s'", expectedStatus, actualStatus)
		}

		log.Print("Valheim service is active!")
		return "", nil
	})
	if err != nil {
		return err
	}

	_, err = retry.DoWithRetryE(t, "Checking if Valheim process is running", 60, 5*time.Second, func() (string, error) {
		out, err := taws.CheckSsmCommandE(t, region, instanceID, "pgrep valheim_server", 3*time.Minute)
		if err != nil {
			return "", fmt.Errorf("Failed to run command")
		}

		log.Print("Checking if PID was found")
		pid := strings.TrimSpace(out.Stdout)
		if pid == "" {
			return "", fmt.Errorf("PID not found")
		}

		log.Print("Valheim process is running!")
		return "", nil
	})
	if err != nil {
		return err
	}

	log.Print("Valheim is running!")
	return nil
}
