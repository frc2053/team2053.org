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

const pages = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    // About page fields
    heroTitle: z.string().optional(),
    heroText: z.string().optional(),
    heroImage: z.string().optional(),
    heroImageAlt: z.string().optional(),
    firstHeading: z.string().optional(),
    firstContent: z.string().optional(),
    frcHeading: z.string().optional(),
    frcContent: z.string().optional(),
    historyHeading: z.string().optional(),
    historyContent: z.string().optional(),
    // Contact page fields
    heading: z.string().optional(),
    introText: z.string().optional(),
    email: z.string().optional(),
    // Sponsor page fields
    pdfPath: z.string().optional(),
    contactEmail: z.string().optional(),
    contactText: z.string().optional(),
    // Current season fields
    kickoffDate: z.string().optional(),
    events: z.array(z.object({
      name: z.string(),
      date: z.string(),
      location: z.string(),
      url: z.string().optional(),
    })).optional(),
    resourcesHeading: z.string().optional(),
    resources: z.array(z.object({
      text: z.string(),
      url: z.string(),
    })).optional(),
    scheduleHeading: z.string().optional(),
    scheduleIntro: z.string().optional(),
    scheduleNote: z.string().optional(),
    preKickoffSchedule: z.object({
      label: z.string(),
      days: z.array(z.object({
        day: z.string(),
        time: z.string(),
      })),
    }).optional(),
    postKickoffSchedule: z.object({
      label: z.string(),
      days: z.array(z.object({
        day: z.string(),
        time: z.string(),
      })),
    }).optional(),
    calendarHeading: z.string().optional(),
    calendarUrl: z.string().optional(),
  }),
});

const sponsors = defineCollection({
  type: 'data',
  schema: z.object({
    name: z.string(),
    logo: z.string(),
    tier: z.enum(['Platinum', 'Gold', 'Silver', 'Bronze']),
    url: z.string().optional(),
    sortOrder: z.number(),
  }),
});

export const collections = { blog, pages, sponsors };