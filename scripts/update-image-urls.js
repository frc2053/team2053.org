import fs from 'fs/promises';
import path from 'path';
import { glob } from 'glob';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CLOUDFRONT_URL = 'https://d2je6s0jo9muku.cloudfront.net';

// Patterns to match local image references
const IMAGE_PATTERNS = [
  // Markdown images: ![alt](/assets/images/image.ext)
  /!\[([^\]]*)\]\(\/assets\/images\/([^)]+)\)/g,

  // HTML img tags: src="/assets/images/image.ext"
  /src="\/assets\/images\/([^"]+)"/g,

  // Frontmatter: featuredImage: '/assets/images/image.ext'
  /featuredImage:\s*['"]\/assets\/images\/([^'"]+)['"]/g,

  // Frontmatter: gameLogo: '/assets/images/image.ext'
  /gameLogo:\s*['"]\/assets\/images\/([^'"]+)['"]/g,
];

async function updateImageUrls() {
  console.log('🔄 Updating image URLs to CloudFront...\n');

  // Load the mapping file
  let urlMapping = {};
  try {
    const mappingContent = await fs.readFile('image-url-mapping.json', 'utf-8');
    urlMapping = JSON.parse(mappingContent);
    console.log(`📋 Loaded ${Object.keys(urlMapping).length} URL mappings\n`);
  } catch (error) {
    console.log('⚠️  No image-url-mapping.json found, will use direct replacement\n');
  }

  // Find all MDX files in blog and history
  const mdxPatterns = [
    'src/content/blog/**/*.mdx',
    'src/pages/history/years/**/*.mdx',
  ];

  let allFiles = [];
  for (const pattern of mdxPatterns) {
    const files = await glob(pattern, { cwd: process.cwd() });
    allFiles = allFiles.concat(files);
  }

  console.log(`📁 Found ${allFiles.length} files to update\n`);

  let totalReplacements = 0;
  let filesModified = 0;

  for (const filePath of allFiles) {
    const fullPath = path.join(process.cwd(), filePath);
    let content = await fs.readFile(fullPath, 'utf-8');
    const originalContent = content;
    let fileReplacements = 0;

    // Replace markdown images: ![alt](/assets/images/image.ext)
    content = content.replace(
      /!\[([^\]]*)\]\(\/assets\/images\/([^)]+)\)/g,
      (match, alt, imagePath) => {
        // Check if extension changed (e.g., .jpg -> .webp)
        const originalUrl = `/assets/images/${imagePath}`;
        let newUrl = urlMapping[originalUrl];

        if (!newUrl) {
          // Direct replacement (no format conversion)
          newUrl = `${CLOUDFRONT_URL}/${imagePath}`;
        }

        fileReplacements++;
        return `![${alt}](${newUrl})`;
      }
    );

    // Replace HTML img src
    content = content.replace(
      /src="\/assets\/images\/([^"]+)"/g,
      (match, imagePath) => {
        const originalUrl = `/assets/images/${imagePath}`;
        let newUrl = urlMapping[originalUrl] || `${CLOUDFRONT_URL}/${imagePath}`;
        fileReplacements++;
        return `src="${newUrl}"`;
      }
    );

    // Replace frontmatter featuredImage
    content = content.replace(
      /featuredImage:\s*['"]\/assets\/images\/([^'"]+)['"]/g,
      (match, imagePath) => {
        const originalUrl = `/assets/images/${imagePath}`;
        let newUrl = urlMapping[originalUrl] || `${CLOUDFRONT_URL}/${imagePath}`;
        fileReplacements++;
        return `featuredImage: '${newUrl}'`;
      }
    );

    // Replace frontmatter gameLogo
    content = content.replace(
      /gameLogo:\s*['"]\/assets\/images\/([^'"]+)['"]/g,
      (match, imagePath) => {
        const originalUrl = `/assets/images/${imagePath}`;
        let newUrl = urlMapping[originalUrl] || `${CLOUDFRONT_URL}/${imagePath}`;
        fileReplacements++;
        return `gameLogo: '${newUrl}'`;
      }
    );

    // Only write if content changed
    if (content !== originalContent) {
      await fs.writeFile(fullPath, content, 'utf-8');
      console.log(`✅ ${filePath} (${fileReplacements} replacements)`);
      totalReplacements += fileReplacements;
      filesModified++;
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log('✅ Image URL update complete!');
  console.log(`  Files modified: ${filesModified}`);
  console.log(`  Total replacements: ${totalReplacements}`);
  console.log('='.repeat(60));
}

updateImageUrls().catch(console.error);
