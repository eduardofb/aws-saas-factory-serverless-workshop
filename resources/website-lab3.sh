#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

if ! [ -x "$(command -v jq)" ]; then
	echo "Installing jq"
    sudo yum install -y jq
fi

echo "Setting environment variables"
MY_AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
echo "AWS Region = $MY_AWS_REGION"

STACK_OUTPUTS=$(aws cloudformation describe-stacks | jq -r '.Stacks[] | select(.Outputs != null) | .Outputs[]')

API_GATEWAY_URL=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "ApiGatewayEndpointLab3") | .OutputValue')
echo "API Gateway Invoke URL = $API_GATEWAY_URL"

S3_WEBSITE_BUCKET=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "WebsiteS3Bucket") | .OutputValue')
echo "S3 website bucket = $S3_WEBSITE_BUCKET"

CLOUDFRONT_DISTRIBUTION=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "CloudFrontDistributionDNS") | .OutputValue')
echo "CloudFront distribution URL = $CLOUDFRONT_DISTRIBUTION"

CLOUDFRONT_DNS=$(echo $CLOUDFRONT_DISTRIBUTION | sed -r -e 's|https://(.*)|\1|g')
CLOUDFRONT_ID=$(aws cloudfront list-distributions | jq -r --arg cloudFrontDNS "${CLOUDFRONT_DNS}" '.DistributionList.Items[] | select(.DomainName == "\($cloudFrontDNS)") | .Id')
echo "CloudFront distribution ID = $CLOUDFRONT_ID"
echo

# Edit src/shared/config.js in the ReactJS codebase
# set base_url to the REST API stage v1 invoke URL
echo "Configuring React to talk to API Gateway"
cd /home/ec2-user/environment/saas-factory-serverless-workshop/lab2/client
sed -i -r -e 's|(^\s+)(base_url: )("https://.+\.execute-api\..+\.amazonaws\.com/v1")|//LAB 2\1\2\3\n\1\2"'"${API_GATEWAY_URL}"'"|g' src/shared/config.js

echo
echo "Installing NodeJS dependencies"
npm install

echo
echo "Building React app"
npm run build

echo
echo "Uploading React app to S3 website bucket"
cd build
aws s3 sync --delete --acl public-read . s3://$S3_WEBSITE_BUCKET

echo
echo "Invalidating CloudFront distribution cache"
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths /\*

echo
echo "Wait for invalidation to complete, then access your website at..."
echo $CLOUDFRONT_DISTRIBUTION
echo

# Order Service lambdas are cold. Warm them up to improve the workshop experience.
curl -s -H "Accept: application/json" -H "Content-Type: application/json" "$API_GATEWAY_URL/orders" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000?source=warmup" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X POST -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X PUT -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X DELETE -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000" > /dev/null

