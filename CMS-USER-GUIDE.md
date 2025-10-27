# Team 2053 CMS User Guide

Welcome to the Team 2053 Content Management System! This guide will help you create and edit content on the team website without needing to write any code.

## Accessing the CMS

1. Go to **https://team2053.org/admin**
2. Click **"Login with GitHub"**
3. Sign in with your GitHub account (or create one if needed - it's free!)
4. Authorize the Team 2053 CMS app
5. You'll be taken to the CMS dashboard

**Note**: You need to be added as a collaborator to the GitHub repository. Ask a team mentor to add you if you can't log in.

## Creating a New Blog Post

1. In the CMS dashboard, click **"Blog Posts"** in the left sidebar
2. Click the **"New Blog Post"** button (top right)
3. Fill in the required fields:
   - **Title**: The main heading of your blog post
   - **Description**: A brief description for SEO and previews
   - **Publish Date**: Select the date you want displayed
   - **Featured Image**: Click to upload the main image
   - **Excerpt**: A short summary that appears in the blog list
   - **Tags**: Add relevant tags like "FRC", "Competition", "Build Season", etc.
   - **Body**: Write your blog post content using the editor

### Using the Rich Text Editor

The editor supports:
- **Bold**, *italic*, and other text formatting
- Headers: Click the heading dropdown or use `##` for h2, `###` for h3
- Bullet lists and numbered lists
- Links: Highlight text and click the link button
- Images: Click the image button to upload (stored on CloudFront CDN)
- Code blocks (if needed)

### Adding Images to Blog Posts

1. In the body text, click where you want the image
2. Click the **image icon** in the toolbar (or write `![alt text](url)` in markdown)
3. Click **"Choose an image"**
4. Either:
   - **Upload a new image**: Drag and drop or click to browse
   - **Choose existing**: Select from previously uploaded images
5. The image will be saved and automatically uploaded to S3/CloudFront

**How Image Upload Works**:
1. When you upload an image, it's saved to the GitHub repository temporarily
2. A GitHub Action automatically:
   - Converts images to WebP format (25-35% smaller file size)
   - Compresses and optimizes (85% quality, looks great!)
   - Resizes to max 1920px (perfect for web viewing)
   - Uploads to AWS S3 / CloudFront CDN
   - Updates your blog post URLs to point to the optimized version
   - Deletes the original from the repo to keep it small
3. The whole process takes 2-3 minutes after you click "Publish"
4. The CMS preview shows the image from the repo while the Action is running

**Image Tips**:
- Use descriptive file names (e.g., `robot-at-competition.jpg` not `IMG_1234.jpg`)
- Take landscape photos when possible (easier to view on different devices)
- Upload any format: JPG, PNG, GIF (will be converted to WebP automatically)
- Don't worry about file size - upload the highest quality you have! The Action will optimize it

### Saving Your Work

- Click **"Save"** - Saves a draft (won't publish to live site yet)
- Click **"Publish"** - Commits changes to GitHub and deploys to live site
- **Note**: After clicking Publish, it takes 2-3 minutes for changes to appear on team2053.org

## Creating a New History Year Page

1. Click **"History Years"** in the left sidebar
2. Click **"New History Year"**
3. Fill in the fields:
   - **Year**: The competition year (e.g., 2025)
   - **Game Title**: The FRC game name (e.g., "2025 Game: Reefscape")
   - **Description**: Brief overview of the season
   - **Robot Name**: What you named your robot
   - **Wins**: Number of wins
   - **Losses**: Number of losses
   - **Events**: List competitions attended (click "Add" for each one)
   - **Awards**: Any awards won (click "Add" for each one)
   - **Featured Image**: Main robot photo
   - **Game Video URL**: YouTube URL for the game reveal video
   - **Game Logo**: Official FRC game logo image
   - **Content**: Write about the robot design, competition experience, team stories, etc.

4. Click **"Publish"** when done

## Editing Existing Content

1. Navigate to **"Blog Posts"** or **"History Years"**
2. Click on the content you want to edit
3. Make your changes
4. Click **"Publish"** to save and deploy

**Your changes will be committed to GitHub with your name**, so everyone can see who made what edits!

## Using CloudFront Images

All images are automatically optimized and served from AWS CloudFront CDN for fast loading worldwide. When you upload images through the CMS:
- They're temporarily saved to the GitHub repo (for CMS preview)
- A GitHub Action automatically optimizes and uploads to AWS S3
- Images are converted to WebP format (much smaller file size, same quality)
- Delivered via CloudFront CDN with worldwide edge caching
- Original images are deleted from the repo to keep it small
- URLs are automatically updated in your blog posts

**Image URLs will look like**: `https://d2je6s0jo9muku.cloudfront.net/image-name.webp`

**Note**: After publishing, it takes 2-3 minutes for the optimization workflow to complete. During this time:
- The CMS preview shows your original image
- The live site initially shows a loading error
- Once the Action completes, the optimized image appears automatically

**Pro Tip**: You can watch the optimization in real-time! After publishing, go to your GitHub repository's **Actions** tab to see the workflow progress.

## Best Practices

### Blog Posts
- Start with an engaging opening paragraph
- Use headers (`##`, `###`) to break up long posts
- Include lots of photos - visual content engages readers!
- Add specific details (dates, locations, team member names)
- Use tags to help people find related posts
- Proofread before publishing

### History Pages
- Focus on what made that year unique
- Include robot specifications and capabilities
- Mention key moments and memorable matches
- Credit team members who contributed significantly
- Add photos showing the robot and team in action
- Include competition results and awards

### Writing Style
- Write in a friendly, enthusiastic tone
- Explain technical terms for general audience
- Tell stories - people connect with narratives
- Celebrate achievements but stay humble
- Give credit where credit is due

## Troubleshooting

### Can't Log In
- Make sure you have a GitHub account
- Ask a team mentor to add you as a repository collaborator
- Check that you're using the correct GitHub account

### Changes Not Appearing on Live Site
- Changes take 2-3 minutes to deploy after publishing
- Check the site in an incognito/private window
- Clear your browser cache (Ctrl+F5 or Cmd+Shift+R)

### Images Not Uploading
- Check file size (keep under 10MB)
- Ensure file is a supported format (JPG, PNG, WEBP, GIF)
- Try a different browser (Chrome or Firefox recommended)
- Check your internet connection

### Accidentally Deleted or Changed Something
- Don't panic! All changes are tracked in Git
- Contact a team mentor - they can restore previous versions
- Every edit is saved with your name and timestamp

### "Error: Unable to Persist Entry"
- Your GitHub session may have expired - try logging out and back in
- Check that you still have write access to the repository
- Make sure you're connected to the internet

## Content Guidelines

### What to Write About
✅ Competition experiences and results
✅ Build season progress and robot features
✅ Team outreach and community events
✅ Sponsor recognition and thank-yous
✅ Team member achievements and milestones
✅ Behind-the-scenes of the team
✅ Technical explanations of robot mechanisms
✅ Lessons learned and team growth

### What to Avoid
❌ Personal contact information (emails, phone numbers, addresses)
❌ Private or sensitive team information
❌ Negative comments about other teams
❌ Copyrighted images you don't have permission to use
❌ Inappropriate language or content
❌ Unverified information or rumors

## Getting Help

**Need assistance?**
- Ask a team mentor or senior team member
- Check the Decap CMS documentation: https://decapcms.org/docs/
- Report technical issues to the team's tech lead
- For GitHub questions: https://docs.github.com/

## Quick Reference

| Task | Steps |
|------|-------|
| **Login** | Go to team2053.org/admin → Login with GitHub |
| **New blog post** | Blog Posts → New Blog Post → Fill fields → Publish |
| **Edit blog post** | Blog Posts → Click post → Edit → Publish |
| **Upload image** | Click image icon → Choose file → Upload |
| **Add tags** | In blog post, "Tags" field → Type tag → Enter → Add more |
| **Preview before publish** | Click "Save" to save draft without publishing |
| **Create history page** | History Years → New History Year → Fill fields → Publish |

## Keyboard Shortcuts (in editor)

- **Bold**: Ctrl+B (Cmd+B on Mac)
- **Italic**: Ctrl+I (Cmd+I on Mac)
- **Link**: Ctrl+K (Cmd+K on Mac)
- **Undo**: Ctrl+Z (Cmd+Z on Mac)
- **Redo**: Ctrl+Shift+Z (Cmd+Shift+Z on Mac)

---

**Remember**: You have the power to tell Team 2053's story! Don't hesitate to create content showcasing the amazing work our team does. Every post helps document our journey and inspire future team members. 🤖🎉

*For questions about this CMS, contact your team mentors or tech lead.*

*Last updated: October 2025*
