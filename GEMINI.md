# GEMINI.md

## Project Overview

This is a Hexo blog project that serves as a personal blog and a template for others to fork. It uses the `next1` theme. The project is configured for automated deployment to GitHub Pages using GitHub Actions.

The main configuration file is `_config.yml`, and the theme configuration is in `themes/next1/_config.yml`. Blog posts are located in the `source/_posts` directory.

## Building and Running

### Local Development

To run the blog locally for development, you can use either npm scripts or Docker.

**Using npm:**

*   Install dependencies: `npm install`
*   Run the development server: `npm run server`
*   Generate static files: `npm run build`
*   Clean the generated files: `npm run clean`
*   Deploy the blog: `npm run deploy`

**Using Docker:**

This project includes a `Dockerfile` and `docker-compose.yml` for a containerized development environment.

1.  Build the Docker image: `docker build -t hexo .`
2.  Start the services: `docker-compose up -d`
3.  Stop the services: `docker-compose down`

### Deployment

The blog is automatically deployed to GitHub Pages when changes are pushed to the `main` branch. The GitHub Actions workflow is defined in `.github/workflows/pages.yml`.

## Development Conventions

### Creating New Posts

To create a new blog post, add a new Markdown file to the `source/_posts` directory. Each post must begin with a front-matter section that includes the title, date, and other metadata.

**Example Front-matter:**

```yaml
---
title: My New Post
date: 2023-10-27 10:00:00
tags:
- hexo
- blog
---

Your post content starts here.
```

### Customization

To customize the theme, you can modify the `themes/next1/_config.yml` file. For more extensive customizations, you can create custom style and layout files in the `source/_data` directory.
