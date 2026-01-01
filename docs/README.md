# Filtored Landing Page

Simple, clean landing page for www.filtored.com

## Structure

- `index.html` - Main HTML page
- `style.css` - All styles
- `script.js` - Email form handling and interactions

## Features

- Responsive design (mobile, tablet, desktop)
- Email signup form (ready to connect to backend)
- Modern gradient background
- Feature cards
- Clean typography

## Deployment Options

### Option 1: Netlify (Recommended - Easiest)
1. Go to [netlify.com](https://netlify.com)
2. Drag and drop the `Filtored` folder
3. Configure custom domain to `www.filtored.com`

### Option 2: Vercel
1. Install Vercel CLI: `npm i -g vercel`
2. Run `vercel` in this directory
3. Follow prompts and add domain

### Option 3: GitHub Pages
1. Create GitHub repo
2. Push these files
3. Enable GitHub Pages in settings
4. Configure custom domain

### Option 4: Traditional Hosting
1. Upload files via FTP to your hosting provider
2. Point domain to hosting

## Email Backend Integration

The email form currently shows a success message. To actually collect emails:

1. **Mailchimp**: Add Mailchimp form action URL
2. **ConvertKit**: Use ConvertKit API
3. **Custom Backend**: Uncomment fetch code in `script.js` and add your API endpoint
4. **Firebase**: Use Firestore to store emails
5. **Google Sheets**: Use Google Apps Script webhook

## Customization

- Colors: Edit CSS variables in `:root` section of `style.css`
- Content: Edit text in `index.html`
- Features: Add/remove feature cards in the `.features` section

## Domain Setup

Point `www.filtored.com` DNS to your hosting provider:
- Netlify: Add CNAME record
- Vercel: Follow their domain instructions
- Traditional: A record to hosting IP
