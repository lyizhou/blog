import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const VAULT_BLOG = '/Users/yiou/Library/Mobile Documents/iCloud~md~obsidian/Documents/Quant_OS/blog/posts';

export const collections = {
	// 作品集
	work: defineCollection({
		loader: glob({ base: './src/content/work', pattern: '**/*.md' }),
		schema: z.object({
			title: z.string(),
			description: z.string(),
			publishDate: z.coerce.date(),
			tags: z.array(z.string()),
			img: z.string(),
			img_alt: z.string().optional(),
		}),
	}),
	// 博客文章（来自 Obsidian vault）
	blog: defineCollection({
		loader: glob({ base: VAULT_BLOG, pattern: '**/*.md' }),
		schema: z.object({
			title: z.string(),
			date: z.coerce.date(),
			tags: z.array(z.string()).optional().default([]),
			draft: z.boolean().optional().default(false),
			description: z.string().optional().default(''),
		}),
	}),
};
