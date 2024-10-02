# React Application Setup and Deployment

This guide covers the setup of a React application using Amazon Cognito for authentication, and deployment options using Amazon S3 with CloudFront or a containerized approach with Nginx and a Load Balancer.

## Prerequisites

- AWS Account
- Node.js installed
- NPM or Yarn installed
- AWS CLI installed and configured

## Setup

### Step 1: Create a Cognito User Pool

1. Go to the Amazon Cognito Console.
2. Click **Manage User Pools** and then **Create a user pool**.
3. Name your user pool and click **Review defaults**.
4. Click **Create pool**.
5. Note the **Pool Id** and **Pool ARN**.

### Step 2: Create a Cognito Identity Pool

1. Go back to the main Cognito console and select **Manage Identity Pools**.
2. Click **Create new identity pool**.
3. Give your identity pool a name, and check **Enable access to unauthenticated identities** if required.
4. Under **Authentication providers**, in the **Cognito** tab, enter your User Pool ID and App client id.
5. Click **Create Pool**.
6. On the next screen, you will be prompted to set up IAM roles for your identity pool. AWS can create default roles for you, or you can choose to edit these roles. It is critical to attach the appropriate permissions to these roles depending on what AWS resources your application will access.

#### Configuring IAM Roles

After the Identity Pool is created, AWS assigns two roles: one for authenticated users and another for unauthenticated users (if enabled). To allow authenticated users to access DynamoDB resources, you must attach a policy with the necessary permissions to the authenticated role.

1. Go to the IAM console.
2. Find the role associated with your Cognito Identity Pool for authenticated users.
3. Click **Attach policies** and then **Create policy**.
4. In the policy editor, paste the following JSON. This policy allows actions on the DynamoDB table used by your application:

    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "VisualEditor0",
                "Effect": "Allow",
                "Action": [
                    "dynamodb:Scan"
                ],
                "Resource": "arn:aws:dynamodb:us-east-1:<AWS-ACCOUNT-ID>:table/cluster-table-clustering-demo"
            }
        ]
    }
    ```

    Be sure to replace `your-aws-account-id` with your actual AWS account ID.

5. Click **Review policy**, give your policy a name, and then click **Create policy**.
6. Attach the newly created policy to the IAM role for authenticated users.

This setup ensures that your application has the necessary permissions to interact with the specified DynamoDB table, following the principle of least privilege by granting only the permissions needed.


### Step 3: Configuration File

1. Create a file named `aws-exports.js` in your React app's `src` directory.
2. Add the following configuration:

   ```javascript
   const awsConfig = {
    aws_project_region: 'AWS_REGION',  // AWS region of Cognito
    aws_cognito_region: 'AWS_REGION',  // AWS region of Cognito
    aws_cognito_identity_pool_id: 'AWS_COGNITO_IDENTITY_POOL',  // Identity pool ID
    aws_user_pools_id: 'AWS_COGNITO_USER_POOL_ID',                // User Pool ID
    aws_user_pools_web_client_id: 'AWS_CONGITO_USER_POOL_APP_CLIENT_ID', // App client ID
    federationTarget: "COGNITO_USER_POOLS" // keep as "COGNITO_USER_POOLS"
    };

    export default awsConfig;
   ```
3. Make sure all the fields above are properly filled, if you're using Terraform to deploy the tool, make sure you can extract and create the file dynamically. 


### Step 4: Build the React Application

1. Navigate to your project directory.
2. Run `npm install` to install all required dependencies.
3. Build your React application by running:
   ```bash
   npm run build
   ```
4. This command creates a build directory containing your static files (HTML, CSS, JS).

## Running the Application Locally

Before deploying your React application, it is crucial to ensure everything functions correctly in a local development environment. Follow these steps to run your application locally:

### Prerequisites for Running Locally

1. **Configure aws-exports.js:**
   - Ensure that you have created `aws-exports.js` in the src directory of your project. This file should include all necessary configurations for Amazon Cognito:
     ```javascript
     const awsConfig = {
        aws_project_region: 'AWS_REGION',  // AWS region of Cognito
        aws_cognito_region: 'AWS_REGION',  // AWS region of Cognito
        aws_cognito_identity_pool_id: 'AWS_COGNITO_IDENTITY_POOL',  // Identity pool ID
        aws_user_pools_id: 'AWS_COGNITO_USER_POOL_ID',                // User Pool ID
        aws_user_pools_web_client_id: 'AWS_CONGITO_USER_POOL_APP_CLIENT_ID', // App client ID
        federationTarget: "COGNITO_USER_POOLS" // keep as "COGNITO_USER_POOLS"
     };
     export default awsConfig;
     ```
   - Replace `your-region`, `identity-pool-id`, `your-user-pool-id`, and `your-app-client-id` with the actual values from your Cognito setup.

2. **Install Project Dependencies:**
   - Open a terminal and navigate to your project directory.
   - Install all necessary dependencies by running:
     ```bash
     npm install
     ```

3. **Start the React Application:**
   - Run the following command to start your React application:
     ```bash
     npm start
     ```
   - This will compile the application and start a development server.

4. **Access the Application:**
   - Open a web browser and navigate to [http://localhost:3000](http://localhost:3000).
   - You should see your React application running locally. Make sure to test all functionalities, especially those interacting with AWS services, to ensure everything is working as expected.

By following these steps, you can run and test your React application locally before moving on to deploy it in a production environment. This local setup is crucial for development and debugging purposes.


## Deployment Options

### Option 1: Deploy to Amazon S3 with CloudFront using Origin Access Identity (OAI)

This method utilizes an Origin Access Identity (OAI) to securely serve your React application's static files from an S3 bucket via CloudFront, without the bucket being publicly accessible.

1. **Create an S3 Bucket:**
   - Navigate to the Amazon S3 service within the AWS Management Console and create a new bucket:
     ```bash
     aws s3 mb s3://your-bucket-name --region your-region
     ```
   - Replace `your-bucket-name` and `your-region` with your specific details.
   - Do not enable public access; keep the default settings which block all public access.

2. **Upload the Build Directory to S3:**
   - Upload your React application's build directory to the S3 bucket using the AWS CLI:
     ```bash
     aws s3 sync build/ s3://your-bucket-name/
     ```

3. **Create an Origin Access Identity (OAI):**
   - Navigate to the CloudFront service in the AWS Management Console.
   - Go to the **Security** section, then click on **Origin Access Identity**.
   - Click **Create Origin Access Identity**.
   - Provide a comment to describe the OAI (e.g., "OAI for React App"), then create it.

4. **Configure S3 Bucket Permissions:**
   - Go to your S3 bucket in the AWS Management Console.
   - Under the **Permissions** tab, click on **Bucket Policy**.
   - Use the following policy, replacing `your-oai-id` and `your-bucket-name` with your specific OAI ID and bucket name:
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Principal": {
                     "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity your-oai-id"
                 },
                 "Action": "s3:GetObject",
                 "Resource": "arn:aws:s3:::your-bucket-name/*"
             }
         ]
     }
     ```

5. **Create a CloudFront Distribution:**
   - Go back to the CloudFront console and create a new distribution.
   - For the origin source, select your S3 bucket.
   - Enter the Origin Access Identity you just created.
   - Set the origin to use HTTPS only.
   - Set the Viewer Protocol Policy to "Redirect HTTP to HTTPS" for security.
   - Optionally, specify your index document under the Default Root Object, such as `index.html`.
   - Create the distribution.
   - Note the distribution's domain name provided by CloudFront.

6. **Update DNS Records:**
   - If you have a domain name, update your DNS settings to create a CNAME record that points to your CloudFront distribution's domain name.

### Option 2: Containerize with Nginx and Deploy Using a Load Balancer

- Create Docker from with Nginx
- Host the static files from the React `build` folder
- Expose port
- Create ALB
- ACM is used to store the certificate for your load balancer. For demonstration purposes, we are utilizing a self-signed certificate stored in ACM. However, for production applications, it is recommended to obtain a certificate from a trusted Certificate Authority (CA), which can be either external or internal.

## Package Considerations

We leverage AWS Amplify package for the frontend which has certain dependencies that will trigger an NPM audit. Either update to a newer version or use leverage a different frontend/library to avoid the following:
```
Dependency: fast-xml-parser Version: 4.2.5 (npm)
Dependency: nth-check Version: 1.0.2 (npm)
Dependency: fast-xml-parser Version: 4.3.6 (npm)
Dependency: webpack Version: 5.91.0 (npm)
Dependency: postcss Version: 7.0.39 (npm)
Dependency: braces Version: 3.0.2 (npm)
```

## Conclusion

These steps guide you through deploying your React application using AWS Cognito for authentication. Choose between a secure, serverless deployment using Amazon S3 with CloudFront or a containerized approach using Nginx for traditional server-based hosting.

