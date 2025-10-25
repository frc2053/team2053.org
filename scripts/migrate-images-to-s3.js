import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import sharp from 'sharp';
import { glob } from 'glob';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: '.env.local' });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const config = {
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  region: process.env.AWS_REGION || 'us-east-1',
  bucket: process.env.AWS_S3_BUCKET,
  cloudFrontUrl: process.env.CLOUDFRONT_URL,
};

// Image optimization settings
const IMAGE_OPTIMIZATION = {
  maxWidth: 1920,
  maxHeight: 1920,
  quality: 85, // WebP quality (0-100)
  convertToWebP: true, // Convert all images to WebP
  preserveOriginalIfWebP: true, // If already WebP, just optimize
};

// Validate configuration
if (!config.accessKeyId || !config.secretAccessKey || !config.bucket) {
  console.error('❌ Missing AWS credentials in .env.local file!');
  console.error('Please add:');
  console.error('  AWS_ACCESS_KEY_ID=your_access_key');
  console.error('  AWS_SECRET_ACCESS_KEY=your_secret_key');
  console.error('  AWS_S3_BUCKET=team2053-website-assets');
  process.exit(1);
}

// Initialize S3 client
const s3Client = new S3Client({
  region: config.region,
  credentials: {
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
  },
});

/**
 * Optimize image using Sharp
 * @param {Buffer} imageBuffer - Original image buffer
 * @param {string} originalPath - Original file path for reference
 * @returns {Promise<{buffer: Buffer, contentType: string, extension: string}>}
 */
async function optimizeImage(imageBuffer, originalPath) {
  const ext = path.extname(originalPath).toLowerCase();

  try {
    const image = sharp(imageBuffer);
    const metadata = await image.metadata();

    console.log(`  📊 Original: ${metadata.width}x${metadata.height}, ${metadata.format}, ${(imageBuffer.length / 1024).toFixed(1)}KB`);

    // Determine if we should convert to WebP
    const isAlreadyWebP = ext === '.webp';
    const shouldConvertToWebP = IMAGE_OPTIMIZATION.convertToWebP && !isAlreadyWebP;

    // Resize if needed
    let processedImage = image.resize({
      width: IMAGE_OPTIMIZATION.maxWidth,
      height: IMAGE_OPTIMIZATION.maxHeight,
      fit: 'inside',
      withoutEnlargement: true,
    });

    let outputBuffer;
    let contentType;
    let newExtension;

    if (shouldConvertToWebP) {
      // Convert to WebP
      outputBuffer = await processedImage
        .webp({ quality: IMAGE_OPTIMIZATION.quality })
        .toBuffer();
      contentType = 'image/webp';
      newExtension = '.webp';
      console.log(`  ✨ Converted to WebP`);
    } else if (isAlreadyWebP) {
      // Already WebP, just optimize
      outputBuffer = await processedImage
        .webp({ quality: IMAGE_OPTIMIZATION.quality })
        .toBuffer();
      contentType = 'image/webp';
      newExtension = '.webp';
      console.log(`  ✨ Optimized WebP`);
    } else {
      // Keep original format but optimize
      if (ext === '.jpg' || ext === '.jpeg') {
        outputBuffer = await processedImage.jpeg({ quality: IMAGE_OPTIMIZATION.quality }).toBuffer();
        contentType = 'image/jpeg';
        newExtension = ext;
      } else if (ext === '.png') {
        outputBuffer = await processedImage.png({ quality: IMAGE_OPTIMIZATION.quality }).toBuffer();
        contentType = 'image/png';
        newExtension = ext;
      } else {
        // Unsupported format, use original
        outputBuffer = imageBuffer;
        contentType = `image/${metadata.format}`;
        newExtension = ext;
        console.log(`  ⚠️  Unsupported format, uploading as-is`);
      }
    }

    const newMetadata = await sharp(outputBuffer).metadata();
    const sizeSaved = ((1 - outputBuffer.length / imageBuffer.length) * 100).toFixed(1);
    console.log(`  ✅ Optimized: ${newMetadata.width}x${newMetadata.height}, ${(outputBuffer.length / 1024).toFixed(1)}KB (${sizeSaved}% smaller)`);

    return {
      buffer: outputBuffer,
      contentType,
      extension: newExtension,
    };
  } catch (error) {
    console.error(`  ❌ Error optimizing image: ${error.message}`);
    console.log(`  ⚠️  Uploading original file`);

    // Return original if optimization fails
    let contentType = 'image/jpeg'; // default
    if (ext === '.png') contentType = 'image/png';
    else if (ext === '.webp') contentType = 'image/webp';
    else if (ext === '.gif') contentType = 'image/gif';

    return {
      buffer: imageBuffer,
      contentType,
      extension: ext,
    };
  }
}

/**
 * Upload file to S3
 */
async function uploadToS3(fileBuffer, s3Key, contentType) {
  const upload = new Upload({
    client: s3Client,
    params: {
      Bucket: config.bucket,
      Key: s3Key,
      Body: fileBuffer,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000', // Cache for 1 year
    },
  });

  await upload.done();
}

/**
 * Main migration function
 */
async function migrateImages() {
  console.log('🚀 Starting image migration to S3 with optimization...\n');
  console.log('Configuration:');
  console.log(`  Bucket: ${config.bucket}`);
  console.log(`  Region: ${config.region}`);
  console.log(`  CloudFront: ${config.cloudFrontUrl}`);
  console.log(`  Max dimensions: ${IMAGE_OPTIMIZATION.maxWidth}x${IMAGE_OPTIMIZATION.maxHeight}`);
  console.log(`  Convert to WebP: ${IMAGE_OPTIMIZATION.convertToWebP ? 'Yes' : 'No'}`);
  console.log(`  Quality: ${IMAGE_OPTIMIZATION.quality}%\n`);

  // Find all images in public/assets/images
  const imagesDir = path.join(process.cwd(), 'public', 'assets', 'images');
  const imagePatterns = ['**/*.jpg', '**/*.jpeg', '**/*.png', '**/*.webp', '**/*.gif'];

  let allImages = [];
  for (const pattern of imagePatterns) {
    const images = await glob(pattern, { cwd: imagesDir });
    allImages = allImages.concat(images);
  }

  console.log(`📁 Found ${allImages.length} images to migrate\n`);

  let successCount = 0;
  let errorCount = 0;
  const urlMapping = {}; // Track old path -> new CloudFront URL

  for (let i = 0; i < allImages.length; i++) {
    const relativePath = allImages[i];
    const fullPath = path.join(imagesDir, relativePath);

    console.log(`[${i + 1}/${allImages.length}] Processing: ${relativePath}`);

    try {
      // Read the file
      const fileBuffer = await fs.readFile(fullPath);

      // Optimize the image
      const { buffer: optimizedBuffer, contentType, extension } = await optimizeImage(fileBuffer, fullPath);

      // Determine S3 key (path in S3)
      // Replace extension if converted to WebP
      let s3Key = relativePath;
      if (extension !== path.extname(relativePath)) {
        s3Key = relativePath.replace(path.extname(relativePath), extension);
      }

      // Upload to S3
      await uploadToS3(optimizedBuffer, s3Key, contentType);

      // Store URL mapping for later reference
      const oldUrl = `/assets/images/${relativePath}`;
      const newUrl = `${config.cloudFrontUrl}/${s3Key}`;
      urlMapping[oldUrl] = newUrl;

      console.log(`  ✅ Uploaded to S3: ${s3Key}`);
      console.log(`  🌐 CloudFront URL: ${newUrl}\n`);

      successCount++;
    } catch (error) {
      console.error(`  ❌ Error: ${error.message}\n`);
      errorCount++;
    }
  }

  // Save URL mapping to file for reference
  const mappingPath = path.join(process.cwd(), 'image-url-mapping.json');
  await fs.writeFile(mappingPath, JSON.stringify(urlMapping, null, 2));

  console.log('\n' + '='.repeat(60));
  console.log('✅ Migration complete!');
  console.log(`  Success: ${successCount}`);
  console.log(`  Errors: ${errorCount}`);
  console.log(`  URL mapping saved to: image-url-mapping.json`);
  console.log('='.repeat(60));
}

// Run migration
migrateImages().catch(console.error);
