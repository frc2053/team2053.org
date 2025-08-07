import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    publishDate: z.date(),
    featuredImage: z.string().optional(),
    excerpt: z.string(),
    tags: z.array(z.string()).optional(),
    authors: z.array(z.string()).optional(),
  }),
});

export const collections = { blog };