import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

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
	// 博客文章（从 Obsidian vault 同步到此目录，用 scripts/publish.sh 发布）
	blog: defineCollection({
		loader: glob({ base: './src/content/blog', pattern: '**/*.md' }),
		schema: z.object({
			title: z.string(),
			date: z.coerce.date(),
			tags: z.array(z.string()).optional().default([]),
			draft: z.boolean().optional().default(false),
			description: z.string().optional().default(''),
		}),
	}),
};
