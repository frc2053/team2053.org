#!/usr/bin/env node

import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import sharp from 'sharp';

// Load environment variables
dotenv.config({ path: '.env.local' });

const s3Client = new S3Client({
  region: process.env.AWS_REGION,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

async function optimizeAndUploadImage(localPath) {
  const fileName = path.basename(localPath);
  const fileExt = path.extname(fileName).toLowerCase();

  console.log(`\n📸 Processing: ${fileName}`);

  try {
    let fileBuffer;
    let contentType;
    let s3Key = fileName;

    // Only optimize raster images, not SVGs
    if (['.jpg', '.jpeg', '.png', '.gif'].includes(fileExt)) {
      // Convert to WebP and optimize
      const webpFileName = fileName.replace(/\.(jpg|jpeg|png|gif)$/i, '.webp');
      s3Key = webpFileName;

      console.log(`  ⚙️  Converting to WebP and optimizing...`);
      fileBuffer = await sharp(localPath)
        .resize(1920, 1920, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 85 })
        .toBuffer();

      contentType = 'image/webp';
      console.log(`  ✓ Converted ${fileName} → ${webpFileName}`);
    } else if (fileExt === '.svg') {
      // Upload SVG as-is
      fileBuffer = fs.readFileSync(localPath);
      contentType = 'image/svg+xml';
      console.log(`  ✓ Using original SVG`);
    } else {
      // Upload other formats as-is
      fileBuffer = fs.readFileSync(localPath);
      contentType = `image/${fileExt.slice(1)}`;
      console.log(`  ✓ Using original format`);
    }

    // Upload to S3
    const command = new PutObjectCommand({
      Bucket: process.env.AWS_S3_BUCKET,
      Key: s3Key,
      Body: fileBuffer,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000',
    });

    await s3Client.send(command);
    console.log(`  ✅ Uploaded to S3: ${s3Key}`);
    console.log(`  🌐 URL: ${process.env.CLOUDFRONT_URL}/${s3Key}`);

    return {
      success: true,
      originalFile: fileName,
      s3Key: s3Key,
      url: `${process.env.CLOUDFRONT_URL}/${s3Key}`,
    };
  } catch (error) {
    console.error(`  ❌ Failed to upload ${fileName}:`, error.message);
    return { success: false, originalFile: fileName, error: error.message };
  }
}

async function main() {
  const imagePath = process.argv[2];

  if (!imagePath) {
    console.error('Usage: node scripts/upload-cms-image-to-s3.js <image-path>');
    console.error('Example: node scripts/upload-cms-image-to-s3.js public/assets/images/tapebumper.jpg');
    process.exit(1);
  }

  if (!fs.existsSync(imagePath)) {
    console.error(`❌ File not found: ${imagePath}`);
    process.exit(1);
  }

  console.log('🚀 Starting S3 upload...');
  const result = await optimizeAndUploadImage(imagePath);

  if (result.success) {
    console.log('\n✅ Done!');
    console.log(`\nUpdate your blog post to use: ${result.url}`);
    if (result.s3Key !== result.originalFile) {
      console.log(`\n⚠️  Note: File was converted from ${result.originalFile} to ${result.s3Key}`);
    }
  } else {
    console.error('\n❌ Upload failed');
    process.exit(1);
  }
}

main().catch(console.error);
