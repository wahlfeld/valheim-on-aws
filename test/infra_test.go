package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestTerraform(t *testing.T) {
	t.Parallel()

	region := aws.GetRandomStableRegion(t, nil, nil)
	uniqueID := strings.ToLower(random.UniqueId())
	stateBucket := fmt.Sprintf("%s-terratest", uniqueID)
	key := fmt.Sprintf("%s/terraform.tfstate", uniqueID)

	defer cleanUpStateBucket(t, region, stateBucket)
	aws.CreateS3Bucket(t, region, stateBucket)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./",
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

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// contents := aws.GetS3ObjectContents(t, region, stateBucket, key)
	// require.Contains(t, contents, uniqueID)

	bucketID := terraform.Output(t, terraformOptions, "bucket_id")

	actualStatus := aws.GetS3BucketVersioning(t, region, bucketID)
	expectedStatus := "Enabled"
	assert.Equal(t, expectedStatus, actualStatus)

	aws.AssertS3BucketPolicyExists(t, region, bucketID)
}

func cleanUpStateBucket(t *testing.T, region string, stateBucket string) {
	aws.EmptyS3Bucket(t, region, stateBucket)
	aws.DeleteS3Bucket(t, region, stateBucket)
}
