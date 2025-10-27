# GitHub Secrets Setup for S3 Image Upload

The GitHub Actions workflow needs AWS credentials to upload images to S3. Follow these steps to add them as repository secrets.

## Required Secrets

You need to add 5 secrets to your GitHub repository:

1. `AWS_ACCESS_KEY_ID`
2. `AWS_SECRET_ACCESS_KEY`
3. `AWS_REGION`
4. `AWS_S3_BUCKET`
5. `CLOUDFRONT_DOMAIN`

## How to Add Secrets

1. Go to your GitHub repository: https://github.com/frc2053/team2053.org

2. Click on **Settings** (top right tab)

3. In the left sidebar, click **Secrets and variables** → **Actions**

4. Click **New repository secret**

5. Add each secret one by one:

### Secret 1: AWS_ACCESS_KEY_ID
- **Name**: `AWS_ACCESS_KEY_ID`
- **Value**: Get this from your `.env.local` file (the `AWS_ACCESS_KEY_ID` value)

### Secret 2: AWS_SECRET_ACCESS_KEY
- **Name**: `AWS_SECRET_ACCESS_KEY`
- **Value**: Get this from your `.env.local` file (the `AWS_SECRET_ACCESS_KEY` value)
- ⚠️ **Important**: This is a secret key - never commit it to the repository!

### Secret 3: AWS_REGION
- **Name**: `AWS_REGION`
- **Value**: `us-east-1`

### Secret 4: AWS_S3_BUCKET
- **Name**: `AWS_S3_BUCKET`
- **Value**: `team2053-website-assets`

### Secret 5: CLOUDFRONT_DOMAIN
- **Name**: `CLOUDFRONT_DOMAIN`
- **Value**: `d2je6s0jo9muku.cloudfront.net`

## How It Works

Once you add these secrets:

1. When you upload an image through the CMS, it gets committed to `public/assets/images/`
2. The GitHub Action automatically:
   - Detects the new image file
   - Converts to WebP format (25-35% smaller file size)
   - Optimizes and compresses (85% quality)
   - Resizes to max 1920px width
   - Uploads to S3 with proper content-type and cache headers
   - Updates all blog post URLs to point to the optimized CloudFront version
   - Deletes the original image from the repo to keep it small
3. The optimized image is available at `https://d2je6s0jo9muku.cloudfront.net/filename.webp`
4. The entire process takes 2-3 minutes

## Testing

After adding the secrets:

1. Create a new blog post in the CMS
2. Upload an image
3. Save and publish the post
4. Go to GitHub **Actions** tab
5. You should see the workflow run automatically
6. Check the workflow output to confirm the image was uploaded to S3

## Security Note

- These secrets are encrypted and only accessible to GitHub Actions workflows
- Never commit `.env.local` to the repository (it's already in `.gitignore`)
- The IAM user has minimal permissions (only S3 upload access to this bucket)
- If you suspect the credentials have been compromised, rotate them immediately in the AWS IAM console
