import fs from 'fs/promises';
import path from 'path';
import { glob } from 'glob';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CLOUDFRONT_URL = 'https://d2je6s0jo9muku.cloudfront.net';

async function updateComponentImages() {
  console.log('🔄 Updating image URLs in Astro components...\n');

  // Load the mapping file
  let urlMapping = {};
  try {
    const mappingContent = await fs.readFile('image-url-mapping.json', 'utf-8');
    urlMapping = JSON.parse(mappingContent);
    console.log(`📋 Loaded ${Object.keys(urlMapping).length} URL mappings\n`);
  } catch (error) {
    console.log('⚠️  No image-url-mapping.json found');
    process.exit(1);
  }

  // Find all Astro and TypeScript files
  const filePatterns = [
    'src/**/*.astro',
    'src/**/*.ts',
  ];

  let allFiles = [];
  for (const pattern of filePatterns) {
    const files = await glob(pattern, { cwd: process.cwd() });
    allFiles = allFiles.concat(files);
  }

  console.log(`📁 Found ${allFiles.length} files to check\n`);

  let totalReplacements = 0;
  let filesModified = 0;

  for (const filePath of allFiles) {
    const fullPath = path.join(process.cwd(), filePath);
    let content = await fs.readFile(fullPath, 'utf-8');
    const originalContent = content;
    let fileReplacements = 0;

    // Replace all /assets/images/ references
    content = content.replace(
      /(['"`])\/assets\/images\/([^'"`]+)(['"`])/g,
      (match, quote1, imagePath, quote2) => {
        const originalUrl = `/assets/images/${imagePath}`;
        let newUrl = urlMapping[originalUrl];

        if (!newUrl) {
          // Direct replacement if not in mapping
          newUrl = `${CLOUDFRONT_URL}/${imagePath}`;
        }

        fileReplacements++;
        return `${quote1}${newUrl}${quote2}`;
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
  console.log('✅ Component image URL update complete!');
  console.log(`  Files modified: ${filesModified}`);
  console.log(`  Total replacements: ${totalReplacements}`);
  console.log('='.repeat(60));
}

updateComponentImages().catch(console.error);
