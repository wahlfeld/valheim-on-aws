package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var uniqueID string = strings.ToLower(random.UniqueId())
var stateBucket string = fmt.Sprintf("%s-terratest", uniqueID)
var key string = fmt.Sprintf("%s/terraform.tfstate", uniqueID)

func TestTerraform(t *testing.T) {
	t.Parallel()

	workingDir := "./"
	region := aws.GetRandomStableRegion(t, nil, nil)

	defer test_structure.RunTestStage(t, "teardown_state_bucket", func() {
		cleanUpStateBucket(t, region, stateBucket)
	})

	defer test_structure.RunTestStage(t, "teardown_terraform", func() {
		undeployUsingTerraform(t, workingDir)
	})

	test_structure.RunTestStage(t, "create_state_bucket", func() {
		aws.CreateS3Bucket(t, region, stateBucket)
	})

	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, region, workingDir)
	})

	test_structure.RunTestStage(t, "check_state_bucket", func() {
		contents := aws.GetS3ObjectContents(t, region, stateBucket, key)
		require.Contains(t, contents, uniqueID)
	})

	test_structure.RunTestStage(t, "check_s3_bucket_config", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		bucketID := terraform.Output(t, terraformOptions, "bucket_id")

		actualStatus := aws.GetS3BucketVersioning(t, region, bucketID)
		expectedStatus := "Enabled"
		assert.Equal(t, expectedStatus, actualStatus)

		aws.AssertS3BucketPolicyExists(t, region, bucketID)
	})

	test_structure.RunTestStage(t, "test_instance_ssm", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

		instanceID := terraform.Output(t, terraformOptions, "instance_id")
		timeout := 3 * time.Minute

		aws.WaitForSsmInstance(t, region, instanceID, timeout)

		result := aws.CheckSsmCommand(t, region, instanceID, "echo Hello, World", timeout)
		require.Equal(t, result.Stdout, "Hello, World\n")
		require.Equal(t, result.Stderr, "")
		require.Equal(t, int64(0), result.ExitCode)

		result, err := aws.CheckSsmCommandE(t, region, instanceID, "cat /wrong/file", timeout)
		require.Error(t, err)
		require.Equal(t, "Failed", err.Error())
		require.Equal(t, "cat: /wrong/file: No such file or directory\nfailed to run commands: exit status 1", result.Stderr)
		require.Equal(t, "", result.Stdout)
		require.Equal(t, int64(1), result.ExitCode)
	})
}

func deployUsingTerraform(t *testing.T, region string, workingDir string) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: workingDir,
		Vars: map[string]interface{}{
			"aws_region":       region,
			"domain":           "",
			"instance_type":    "t3.nano",
			"keybase_username": "marypoppins",
			"sns_email":        "fake@email.com",
			"world_name":       "test-world",
			"server_name":      "test-server",
			"server_password":  "test-password",
			"purpose":          "test",
			"unique_id":        uniqueID,
			"admins": map[string]interface{}{
				"user1": 76561197993928956,
				"user2": 76561197994340320,
				"user3": "",
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
	aws.EmptyS3Bucket(t, region, stateBucket)
	aws.DeleteS3Bucket(t, region, stateBucket)
}
