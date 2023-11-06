package test

import (
	"crypto/tls"
	"fmt"
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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"

	taws "github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

const worldFilesLocalDirectory = "/home/vhserver/.config/unity3d/IronGate/Valheim/worlds_local"
const worldName string = "test-world"

var uniqueID string = strings.ToLower(random.UniqueId())
var stateBucket string = fmt.Sprintf("%s-terratest-valheim", uniqueID)
var key string = fmt.Sprintf("%s/terraform.tfstate", uniqueID)
var worldFileFwlName = fmt.Sprintf("%s.fwl", worldName)
var worldFileDbName = fmt.Sprintf("%s.db", worldName)
var worldFileLocalPaths = map[string]string{
	"fwl": fmt.Sprintf("%s/%s", worldFilesLocalDirectory, worldFileFwlName),
	"db":  fmt.Sprintf("%s/%s", worldFilesLocalDirectory, worldFileDbName),
}

// FunctionWithError is a function type that returns an error
type FunctionWithError func() error

func TestTerraform(t *testing.T) {
	t.Parallel()

	workingDirectory := "./template"
	region := taws.GetRandomStableRegion(t, nil, nil)

	sess := session.Must(session.NewSession(&aws.Config{
		Region: aws.String(region),
	}))

	defer test_structure.RunTestStage(t, "teardown_terraform_and_state_bucket", func() {
		_, err := undeployUsingTerraform(t, workingDirectory)
		if err != nil {
			t.Fatal("Terraform destroy failed, skipping state bucket teardown. Manual intervention required.")
			t.SkipNow()
		}
		emptyAndDeleteBucket(t, region, stateBucket)
	})

	defer test_structure.RunTestStage(t, "logs", func() {
		fetchSyslogForInstance(t, region, workingDirectory)
	})

	test_structure.RunTestStage(t, "create_state_bucket", func() {
		taws.CreateS3Bucket(t, region, stateBucket)
	})

	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, region, workingDirectory)
	})

	test_structure.RunTestStage(t, "check_state_bucket", func() {
		contents := taws.GetS3ObjectContents(t, region, stateBucket, key)
		require.Contains(t, contents, uniqueID)
	})

	test_structure.RunTestStage(t, "check_s3_bucket_config", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		actualStatus := taws.GetS3BucketVersioning(t, region, bucketID)
		expectedStatus := "Enabled"
		assert.Equal(t, expectedStatus, actualStatus)

		taws.AssertS3BucketPolicyExists(t, region, bucketID)
	})

	test_structure.RunTestStage(t, "test_instance_ssm", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		timeout := 3 * time.Minute

		// Make sure SSM is ready before trying to connect
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
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

		monitoringURL := terraform.Output(t, terraformOptions, "monitoring_url")

		validateResponse(t, monitoringURL, 30, 5*time.Second)
	})

	test_structure.RunTestStage(t, "check_valheim_service", func() {
		// Given the instance is now running and SSM is available
		// Expect the Valheim to be running

		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)
		instanceID := terraform.Output(t, terraformOptions, "instance_id")

		// Make sure SSM is ready before trying to connect
		taws.WaitForSsmInstance(t, region, instanceID, 3*time.Minute)

		err := checkValheimIsRunning(t, region, instanceID)
		require.NoError(t, err, "Valheim is not running. Error: %v", err)
	})

	test_structure.RunTestStage(t, "test_backup", func() {
		// Given the instance is running and SSM is available
		// When it is stopped and started again
		// Expect the world files to be present in the backup S3 bucket

		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		// .db file is not created immediately by Valheim, so we instantiate it
		_, err := runCommandWithRetry(t, fmt.Sprintf("Instantiating .db world file %s", worldFileLocalPaths["db"]), 2, 30*time.Second, region, instanceID, fmt.Sprintf("touch %s", worldFileLocalPaths["db"]), 5*time.Second)
		if err != nil {
			// Ensure bucket is emptied so that Terraform can destroy it
			emptyAndDeleteBucket(t, region, bucketID)
			t.Fatalf("Error running command: %v", err)
		}

		err = startStopInstance(t, sess, instanceID)
		if err != nil {
			// Ensure bucket is emptied so that Terraform can destroy it
			emptyAndDeleteBucket(t, region, bucketID)
			t.Fatalf("Error stopping and starting instance: %v", err)
		}

		worldFileNames := []string{worldFileFwlName, worldFileDbName}
		_, err = retry.DoWithRetryE(t, fmt.Sprintf("Checking that world files exist in S3 bucket %s", bucketID), 5, 5*time.Second, func() (string, error) {
			err = checkFilesExistInBucket(t, sess, bucketID, worldFileNames)
			if err != nil {
				return "", fmt.Errorf("files %v not found in bucket %s: %v", worldFileNames, bucketID, err)
			}
			return "", nil
		})
		if err != nil {
			// Ensure bucket is emptied so that Terraform can destroy it
			emptyAndDeleteBucket(t, region, bucketID)
			t.Fatal(err)
		}

		t.Log("Files found in bucket")
	})

	test_structure.RunTestStage(t, "test_restore", func() {
		// Given the instance is running and SSM is available
		// When it is started and no local world files are present
		// Expect the backup S3 bucket world files to be used

		terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		// Ensure bucket is emptied so that Terraform can destroy it
		defer emptyAndDeleteBucket(t, region, bucketID)

		// Make sure SSM is ready before trying to connect
		taws.WaitForSsmInstance(t, region, instanceID, 3*time.Minute)

		// Stop Valheim service before removing local world files
		_, err := valheimService(t, region, instanceID, "stop")
		require.NoError(t, err)

		// Remove any local world files if they exist
		for _, worldFileLocalPath := range worldFileLocalPaths {
			_, err := runCommandWithRetry(t, "Removing local world files", 2, 30*time.Second, region, instanceID, fmt.Sprintf("rm -rf %s", worldFileLocalPath), 5*time.Second)
			require.NoError(t, err, "Error running command: %v", err)
		}

		_, err = valheimService(t, region, instanceID, "start")
		require.NoError(t, err)

		err = checkValheimIsRunning(t, region, instanceID)
		require.NoError(t, err, "Valheim is not running")

		_, err = retry.DoWithRetryE(t, "Checking if backups were restored from S3", 2, 60*time.Second, func() (string, error) {
			output, err := taws.CheckSsmCommandE(t, region, instanceID, "grep 'Backups found, restoring...' /var/log/syslog", 3*time.Minute)
			if err != nil {
				return "", fmt.Errorf("command output was '%+v' and error was '%v'", output, err)
			}

			t.Log("Checking if log was found")
			if output == nil {
				return "", fmt.Errorf("log not found (was nil)")
			}

			if output.Stdout == "" {
				return "", fmt.Errorf("log not found (was \"\")")
			}

			return "", nil
		})
		require.NoError(t, err)

		t.Log("Log found")

		t.Log("############")
		t.Log("### PASS ###")
		t.Log("############")
		t.Logf("Emptying and deleting bucket %s now, so that Terraform can destroy it", bucketID)
		t.Log("Skipping syslog...")
		os.Setenv("SKIP_logs", "true")
	})
}

func deployUsingTerraform(t *testing.T, region string, workingDirectory string) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: workingDirectory,
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

	test_structure.SaveTerraformOptions(t, workingDirectory, terraformOptions)

	maxRetries := 2
	for attempt := 0; attempt <= maxRetries; attempt++ {
		// Run Terraform Init and Apply and capture any errors
		_, err := terraform.InitAndApplyE(t, terraformOptions)
		if err == nil {
			// If there's no error, break out of the loop
			break
		}

		// Convert the error to a string for parsing
		errMsg := fmt.Sprintf("%v", err)

		// Check if the error message contains the specific substrings related to spot instance errors
		if strings.Contains(errMsg, "Error waiting for spot instance") || strings.Contains(errMsg, "bad-parameters") {
			// Log the error and decide to retry
			t.Logf("Attempt %d: Spot instance request error: %v", attempt+1, err)
			if attempt < maxRetries {
				t.Logf("Retrying terraform apply due to spot instance error...")
				continue // Retry the loop
			}
		}

		// If we've reached the maximum number of retries or the error is not spot-related, fail the test
		t.Fatalf("Terraform apply failed after %d attempts with error: %v", attempt+1, err)
	}
}

func undeployUsingTerraform(t *testing.T, workingDirectory string) (string, error) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)
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

func fetchSyslogForInstance(t *testing.T, region string, workingDirectory string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDirectory)

	instanceID := terraform.OutputRequired(t, terraformOptions, "instance_id")
	logs, err := taws.GetSyslogForInstanceE(t, instanceID, region)
	if err != nil {
		t.Logf("Failed to fetch syslog from instance: %s", err)
	}

	t.Logf("Most recent syslog for Instance %s:\n\n%s\n", instanceID, logs)
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
				return fmt.Errorf("file %s does not exist in the bucket %s", fileName, bucketName)
			}
			return err
		}
	}
	return nil
}

func startStopInstance(t *testing.T, sess *session.Session, instanceID string) error {
	svc := ec2.New(sess)

	t.Logf("Stopping instance %s", instanceID)
	inputStop := &ec2.StopInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	}
	_, err := svc.StopInstances(inputStop)
	if err != nil {
		return err
	}

	t.Logf("Waiting until instance %s has stopped", instanceID)
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
			t.Logf("Timed out waiting for instance %s to be ready to start", instanceID)
			return err
		}
		attempts++
		t.Logf("Starting instance %s (attempt %d)", instanceID, attempts)

		inputStart := &ec2.StartInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		}
		_, err := svc.StartInstances(inputStart)
		if err == nil {
			readyToStart = true
		} else {
			t.Logf("Error starting instance %s: %s", instanceID, err.Error())
			t.Log("Instance not ready to start. Sleeping for 5s and will try again.")
			time.Sleep(5 * time.Second)
		}
	}

	t.Logf("Instance %s was ready to start after %d attempts", instanceID, attempts)

	t.Logf("Waiting until instance %s is running", instanceID)
	err = svc.WaitUntilInstanceRunning(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	if err != nil {
		return err
	}

	return nil
}

func checkValheimIsRunning(t *testing.T, region string, instanceID string) error {
	t.Log("Checking if Valheim is running")
	_, err := retry.DoWithRetryE(t, "Checking if Valheim service is active", 100, 10*time.Second, func() (string, error) {
		output, err := taws.CheckSsmCommandE(t, region, instanceID, "systemctl is-active valheim", 30*time.Second)
		if err != nil {
			t.Logf("Command output was '%+v' and error was '%v'", output, err)
			return "", handleErrorWithSyslog(t, region, instanceID, err)
		}

		expectedStatus := "active"
		actualStatus := strings.TrimSpace(output.Stdout)

		if actualStatus != expectedStatus {
			return "", fmt.Errorf("expected status to be '%s' but was '%s'", expectedStatus, actualStatus)
		}

		t.Log("Valheim service is active")
		return "", nil
	})
	if err != nil {
		return err
	}

	_, err = retry.DoWithRetryE(t, "Checking if Valheim process is running", 100, 10*time.Second, func() (string, error) {
		output, err := taws.CheckSsmCommandE(t, region, instanceID, "pgrep valheim_server", 30*time.Second)
		if err != nil {
			t.Logf("Command output was '%+v' and error was '%v'", output, err)

			output, err := taws.CheckSsmCommandE(t, region, instanceID, "ps aux", 30*time.Second)
			if err != nil {
				return "", fmt.Errorf("error running process list command: %v | output: %v", err, output)
			}

			t.Logf("Running processes:\n%s", output.Stdout)

			return "", handleErrorWithSyslog(t, region, instanceID, err)
		}

		t.Log("Checking if PID was found")
		pid := strings.TrimSpace(output.Stdout)
		if pid == "" {
			return "", fmt.Errorf("PID not found")
		}
		return "", nil
	})
	if err != nil {
		return err
	}

	t.Log("Valheim process is running")
	return nil
}

func runCommandWithRetry(t *testing.T, actionDescription string, maxRetries int, sleepBetweenRetries time.Duration, region string, instanceID string, command string, timeout time.Duration) (string, error) {
	output, err := retry.DoWithRetryE(t, actionDescription, maxRetries, sleepBetweenRetries, func() (string, error) {
		output, err := taws.CheckSsmCommandE(t, region, instanceID, command, timeout)
		if err != nil {
			return "", fmt.Errorf("command output was '%+v' and error was '%v'", output, err)
		}
		return fmt.Sprint(output), nil
	})
	if err != nil {
		return "", err
	}
	return output, nil
}

func valheimService(t *testing.T, region string, instanceID string, action string) (string, error) {
	var actionDescription string

	switch action {
	case "start":
		actionDescription = "Starting Valheim service"
	case "stop":
		actionDescription = "Stopping Valheim service"
	case "restart":
		actionDescription = "Restarting Valheim service"
	default:
		return "", fmt.Errorf("%s is an unsupported action", action)
	}

	command := fmt.Sprintf("systemctl %s valheim.service", action)

	output, err := runCommandWithRetry(t, actionDescription, 2, 30*time.Second, region, instanceID, command, 120*time.Second)
	if err != nil {
		return "", fmt.Errorf("error running command: %v", err)
	}
	return output, nil
}

func fetchSyslog(t *testing.T, region string, instanceID string) string {
	command := "tail -n 50 /var/log/syslog"
	syslogOutput, err := taws.CheckSsmCommandE(t, region, instanceID, command, 30*time.Second)
	if err != nil {
		t.Logf("Failed to get syslog: %+v", err)
		return "Could not retrieve syslog."
	}
	return syslogOutput.Stdout
}

func handleErrorWithSyslog(t *testing.T, region string, instanceID string, err error) error {
	if err != nil {
		syslog := fetchSyslog(t, region, instanceID)
		t.Logf("Error occurred: %+v\nLast 50 lines of syslog:\n%s", err, syslog)
	}
	return err
}
