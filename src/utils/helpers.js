export function generateSlug(string) {
	return string
		.toString()
		.trim()
		.toLowerCase()
		.replace(/\s+/g, '-')
		.replace(/[^\w\-]+/g, '')
		.replace(/\-\-+/g, '-')
		.replace(/^-+/, '')
		.replace(/-+$/, '');
}

export function getAllTags(posts) {
    const allTags = posts
        .flatMap((post) => post.data.tags || [])
        .filter(Boolean);
    
    const uniqueTags = [...new Set(allTags)];
    
    return uniqueTags.map((tag) => ({
        title: tag,
        slug: tag.toLowerCase().replace(/\s+/g, '-'),
    }));
}

export function getPostsByTag(posts, tagName) {
    return posts
        .filter((post) => post.data.tags && post.data.tags.includes(tagName))
        .map((post) => ({
            title: post.data.title,
            description: post.data.description,
            publishDate: post.data.publishDate,
            featuredImage: post.data.featuredImage,
            excerpt: post.data.excerpt,
            href: `/blog/${post.slug}`,
        }))
        .sort((a, b) => b.publishDate.getTime() - a.publishDate.getTime());
}

export function generateTagData(tags) {
    return tags.map((tag) => ({
        title: tag,
        slug: tag.toLowerCase().replace(/\s+/g, '-'),
    }));
}