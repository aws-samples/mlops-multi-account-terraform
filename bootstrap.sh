#!/usr/bin/env bash
# This script will create the required resources for bootstrapping your AWS account.
# It creates: OIDC Identity provider for GitHub, IAM Role, S3 bucket, and DynamoDB table.

export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Turn off paging for AWS CLI output
export AWS_PAGER=""

echo "This script will create the the required resources for bootstrapping your AWS account."
echo Bootstrapping Account: $ACCOUNT_ID
echo " "

read -r -p "Enter AWS Region [eu-west-2]:" AWS_REGION
export AWS_REGION=${AWS_REGION:-"eu-west-2"}

read -r -p "Enter Environment (dev | preprod | prod) [dev]:" Environment
Environment=${Environment:-"dev"}

read -r -p "Enter GitHub Org name [sagemaker-mlops-terraform]:" GITHUB_ORG
GITHUB_ORG=${GITHUB_ORG:-"sagemaker-mlops-terraform"}

read -r -p "Enter TerraformStateBucketPrefix [terraform-state]:" TerraformStateBucketPrefix
TerraformStateBucketPrefix=${TerraformStateBucketPrefix:-"terraform-state"}

read -r -p "Enter TerraformStateLockTableName [terraform-state-locks]:" TerraformStateLockTableName
TerraformStateLockTableName=${TerraformStateLockTableName:-"terraform-state-locks"}

ROLE_NAME="aws-github-oidc-role"


echo " "
echo "====================================================="
echo "Creating OIDC Identity Provider"
aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "1b511abead59c6ce207077c0bf0e0043b1382612"
echo "====================================================="
echo " "

echo "====================================================="
echo "Creating IAM Role: "$ROLE
cat > assume_role_policy.json << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
                    "token.actions.githubusercontent.com:sub": "repo:$GITHUB_ORG/*"
                }
            }
        }
    ]
}
EOL
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://assume_role_policy.json \
    --output json
echo "====================================================="
echo " "

echo "====================================================="
echo "Attaching IAM Policy (Administrator) to the role "
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" \
    --output json
echo "====================================================="
echo " "

echo "====================================================="
echo "Creating S3 Bucket: $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID"
aws s3api create-bucket \
    --bucket $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID \
    --acl private \
    --create-bucket-configuration LocationConstraint=$AWS_REGION \
    --output json
echo "========= Setting bucket Encryption"
aws s3api put-bucket-encryption \
    --bucket $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' \
    --output json
echo "========= Setting Public access block"
aws s3api put-public-access-block \
    --bucket $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    --output json
echo "========= Enabling Bucket versioning"
aws s3api put-bucket-versioning \
    --bucket $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID \
    --versioning-configuration Status=Enabled \
    --output json
echo "========= Applying Bucket Policy"
cat > bucket_policy.json << EOL
{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyDeletingTerraformStateFiles",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:DeleteObject",
                "Resource": "arn:aws:s3:::$TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID/*"
            }
        ]
    }
EOL
aws s3api put-bucket-policy \
    --bucket $TerraformStateBucketPrefix-$Environment-$AWS_REGION-$ACCOUNT_ID \
    --policy file://bucket_policy.json \
    --output json
echo "====================================================="
echo " "

echo "====================================================="
echo "Creating DynamoDB Table: $TerraformStateLockTableName-$Environment"
aws dynamodb create-table \
    --table-name $TerraformStateLockTableName-$Environment \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --sse-specification Enabled=true
echo "====================================================="
echo " "

echo "====================================================="
echo "Completed!  Account $ACCOUNT_ID bootstrapped."
echo "====================================================="