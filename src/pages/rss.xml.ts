import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import type { APIContext } from 'astro';

export async function GET(context: APIContext) {
	const posts = (await getCollection('blog'))
		.filter(post => !post.data.draft)
		.sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

	return rss({
		title: 'OpenTrading · Blog',
		description: 'lyizhou 的个人博客，记录量化研究与技术实践。',
		site: context.site!,
		items: posts.map(post => ({
			title: post.data.title,
			pubDate: post.data.date,
			description: post.data.description,
			link: `/blog/${post.id}/`,
		})),
	});
}
