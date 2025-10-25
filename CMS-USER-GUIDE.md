# Team 2053 CMS User Guide

Welcome to the Team 2053 Content Management System! This guide will help you create and edit content on the team website without needing to write any code.

## Accessing the CMS

1. Go to **https://team2053.org/admin**
2. Click **"Login with Netlify Identity"**
3. Enter the shared team account credentials (ask a mentor if you don't have these)
4. You'll be taken to the CMS dashboard

## Creating a New Blog Post

1. In the CMS dashboard, click **"Blog Posts"** in the left sidebar
2. Click the **"New Blog Post"** button
3. Fill in the required fields:
   - **Title**: The main heading of your blog post
   - **Description**: A brief description for SEO and previews
   - **Publish Date**: Select the date you want displayed
   - **Featured Image**: Click to upload the main image (will be optimized automatically)
   - **Excerpt**: A short summary that appears in the blog list
   - **Tags**: Add relevant tags like "FRC", "Competition", "Build", etc.
   - **Body**: Write your blog post content using the rich text editor

### Using the Rich Text Editor

The editor supports:
- **Bold**, *italic*, and other text formatting
- Headers (use ## for h2, ### for h3, etc.)
- Bullet lists and numbered lists
- Links: `[link text](url)`
- Images: Click the image button to upload (images are automatically optimized and uploaded to S3)
- Line breaks: Press Enter twice for a new paragraph

### Adding Images to Blog Posts

1. In the body text, click where you want the image
2. Click the **image icon** in the toolbar
3. Either:
   - **Upload a new image**: Click "Upload" and select your file
   - **Choose existing**: Select from previously uploaded images
4. Add alt text (description for accessibility)
5. Click "Insert"

**Note**: All uploaded images are automatically:
- Optimized for web (compressed, converted to WebP)
- Uploaded to AWS S3
- Served via CloudFront CDN (fast worldwide delivery)

### Saving Your Work

- Click **"Save"** (draft) - Saves your work but doesn't publish
- Click **"Publish"** - Commits your changes to GitHub and triggers a site rebuild
- **Important**: After clicking Publish, it takes 2-3 minutes for changes to appear on the live site

## Creating a New History Year Page

1. Click **"History Years"** in the left sidebar
2. Click **"New History Year"**
3. Fill in the fields:
   - **Year**: The competition year (e.g., 2025)
   - **Game Title**: The FRC game name (e.g., "2025 Game: Reefscape")
   - **Description**: Brief overview of the season
   - **Robot Name**: What you named your robot
   - **Wins/Losses**: Competition statistics
   - **Events**: List competitions attended (one per line)
   - **Awards**: Any awards won (one per line)
   - **Featured Image**: Main robot photo
   - **Game Video URL**: YouTube URL for the game reveal
   - **Game Logo**: Official FRC game logo image
   - **Content**: Write about the robot design, competition experience, etc.

4. Click **"Publish"** when done

## Editing Existing Content

1. Navigate to **"Blog Posts"** or **"History Years"**
2. Click on the content you want to edit
3. Make your changes
4. Click **"Publish"** to save and deploy

## Image Best Practices

### Before Uploading
- Use descriptive file names (e.g., `robot-at-competition.jpg` not `IMG_1234.jpg`)
- Take photos in landscape orientation when possible
- Ensure good lighting and clear subjects

### File Sizes
Don't worry too much about file sizes - the CMS automatically:
- Resizes images larger than 1920px
- Compresses images to 85% quality
- Converts to WebP format (25-35% smaller than JPEG)

### Recommended Sizes
- **Featured Images**: 1200x800px or larger
- **In-content images**: 800px wide minimum
- **Logos**: 200-400px wide

## Tips for Writing Great Content

### Blog Posts
- Start with an engaging opening paragraph
- Use headers (##, ###) to break up long posts
- Include lots of photos - visual content is engaging!
- Add specific details (dates, locations, team member names)
- Proofread before publishing

### History Pages
- Focus on what made that year unique
- Include robot specifications and capabilities
- Mention key moments from competitions
- Credit team members who contributed significantly
- Add photos showing the robot in action

## Troubleshooting

### "Cannot connect to repository"
- Make sure you're logged in with the correct account
- Contact a mentor - Git Gateway may need to be re-enabled

### Images not uploading
- Check file size (keep under 10MB before upload)
- Ensure file is a supported format (JPG, PNG, WEBP, GIF)
- Try a different browser (Chrome or Firefox recommended)

### Changes not appearing on live site
- Changes take 2-3 minutes to deploy
- Check Netlify deploy status (mentors can help)
- Clear your browser cache (Ctrl+F5 or Cmd+Shift+R)

### Accidentally deleted something
- Contact a mentor immediately
- All changes are tracked in Git - we can restore anything!

## Content Guidelines

### What to Write About
✅ Competition experiences and results
✅ Build season progress and robot features
✅ Team outreach and community events
✅ Sponsor recognition and thank-yous
✅ Team member achievements
✅ Behind-the-scenes of the team

### What to Avoid
❌ Personal contact information (emails, phone numbers)
❌ Private team information
❌ Negative comments about other teams
❌ Copyrighted images you don't have permission to use
❌ Inappropriate language or content

## Getting Help

**Need assistance?**
- Ask a team mentor
- Check the Decap CMS documentation: https://decapcms.org/docs/
- Report technical issues to the team's tech lead

## Quick Reference

| Task | Steps |
|------|-------|
| **Login** | Go to team2053.org/admin → Login with Netlify Identity |
| **New blog post** | Blog Posts → New Blog Post → Fill fields → Publish |
| **Edit blog post** | Blog Posts → Click post → Edit → Publish |
| **Upload image** | Click image icon → Upload → Select file |
| **Add tags** | In blog post, "Tags" field → Type tag → Enter |
| **Preview changes** | Click "Save" instead of "Publish" → View on staging |

---

**Remember**: You have the power to tell Team 2053's story! Don't hesitate to create content showcasing the amazing work our team does. 🤖🎉

*Last updated: October 2025*
