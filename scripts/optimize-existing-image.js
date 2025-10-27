#!/usr/bin/env node

import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: '.env.local' });

// Extract domain from CLOUDFRONT_URL or use CLOUDFRONT_DOMAIN
const cloudfrontDomain = process.env.CLOUDFRONT_DOMAIN ||
  process.env.CLOUDFRONT_URL?.replace(/^https?:\/\//, '').replace(/\/$/, '');

const s3Client = new S3Client({
  region: process.env.AWS_REGION,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

async function optimizeAndUpload(localPath) {
  const fileName = path.basename(localPath);
  const fileExt = path.extname(fileName).toLowerCase();

  console.log(`\n📸 Processing: ${fileName}`);

  try {
    let fileBuffer;
    let contentType;
    let s3Key = fileName;

    // Optimize raster images
    if (['.jpg', '.jpeg', '.png', '.gif'].includes(fileExt)) {
      const webpFileName = fileName.replace(/\.(jpg|jpeg|png|gif)$/i, '.webp');
      s3Key = webpFileName;

      console.log(`  ⚙️  Converting to WebP and optimizing...`);
      const metadata = await sharp(localPath).metadata();
      console.log(`  📏 Original: ${metadata.width}x${metadata.height}, ${(metadata.size / 1024 / 1024).toFixed(2)}MB`);

      fileBuffer = await sharp(localPath)
        .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 85 })
        .toBuffer();

      const savedPercent = ((1 - fileBuffer.length / metadata.size) * 100).toFixed(1);
      console.log(`  ✓ Optimized: ${(fileBuffer.length / 1024 / 1024).toFixed(2)}MB (${savedPercent}% smaller)`);
      console.log(`  ✓ Converted ${fileName} → ${webpFileName}`);

      contentType = 'image/webp';
    } else {
      console.log(`  ⚠️  Skipping ${fileName} - not a raster image`);
      return { success: false, reason: 'not a raster image' };
    }

    // Upload to S3
    await s3Client.send(new PutObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET,
      Key: s3Key,
      Body: fileBuffer,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000',
    }));

    const url = `https://${cloudfrontDomain}/${s3Key}`;
    console.log(`  ✅ Uploaded to S3: ${s3Key}`);
    console.log(`  🌐 URL: ${url}`);

    return { success: true, originalFile: fileName, s3Key, url };
  } catch (error) {
    console.error(`  ❌ Failed:`, error.message);
    return { success: false, error: error.message };
  }
}

async function main() {
  const imagePath = process.argv[2];

  if (!imagePath) {
    console.error('Usage: node scripts/optimize-existing-image.js <image-path>');
    console.error('Example: node scripts/optimize-existing-image.js public/assets/images/tapebumper.jpg');
    process.exit(1);
  }

  if (!fs.existsSync(imagePath)) {
    console.error(`❌ File not found: ${imagePath}`);
    process.exit(1);
  }

  console.log('🚀 Starting optimization and upload...');
  const result = await optimizeAndUpload(imagePath);

  if (result.success) {
    console.log('\n✅ Done! Optimized image is now available on CloudFront.');
    console.log(`\nOld URL: https://${cloudfrontDomain}/${result.originalFile}`);
    console.log(`New URL: ${result.url}`);
    console.log(`\nYou should now:`);
    console.log(`1. Update any references from ${result.originalFile} to ${result.s3Key}`);
    console.log(`2. Delete the local file: rm ${imagePath}`);
    console.log(`3. Commit the changes`);
  } else {
    console.error('\n❌ Optimization failed');
    process.exit(1);
  }
}

main().catch(console.error);
