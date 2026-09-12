// One social card per docs page, generated at build: limestone ground, the
// mark, a terracotta bar on the leading edge, Fraunces title, Instrument Sans
// line. Slugs match page paths: /og/docs/protocol.png, /og/404.png.
//
// The landing page is not here on purpose. Its card is composed by hand
// (public/img/og.png, source in ../../og.html) because the philosopher and
// the scribe are the half that makes the point, and a title on limestone
// would not be the same card.
import { getCollection } from 'astro:content';
import { OGImageRoute } from 'astro-og-canvas';

const docs = await getCollection('docs');

const pages: Record<string, { title: string; description: string }> = {
	'404': { title: 'Nothing at this path.', description: 'Not a dropped frame — the page was moved, or never existed.' },
	'docs/api/reference': {
		title: 'API reference',
		description: 'Every route and every frame — generated from docs/openapi.yaml.',
	},
	...Object.fromEntries(
		docs.map((e) => [
			e.id === 'index' ? 'docs/index' : `docs/${e.id}`,
			{ title: e.data.title, description: e.data.description },
		]),
	),
};

export const { getStaticPaths, GET } = await OGImageRoute({
	param: 'slug',
	pages,
	getImageOptions: (_id, page) => ({
		title: page.title,
		description: page.description,
		logo: { path: './src/assets/og-mark.png', size: [84] },
		bgGradient: [[250, 242, 228]],
		border: { color: [196, 85, 46], width: 18, side: 'inline-start' },
		padding: 72,
		font: {
			title: {
				color: [42, 33, 26],
				size: 62,
				weight: 'Bold',
				lineHeight: 1.12,
				families: ['Fraunces'],
			},
			description: {
				color: [78, 64, 52],
				size: 28,
				lineHeight: 1.4,
				families: ['Instrument Sans'],
			},
		},
		fonts: ['./src/assets/og-fonts/Fraunces.ttf', './src/assets/og-fonts/InstrumentSans.ttf'],
	}),
});
