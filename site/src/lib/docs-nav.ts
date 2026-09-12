// The docs tree, in reading order. Modelled on Pteroprompter's docs and the
// tree Rheocles settled; each entry is a collection id under
// src/content/docs, except the API reference, which is a page of its own
// generated from docs/openapi.yaml. A page that does not exist yet still
// appears in the sidebar, unlinked, so the shape of the docs is visible
// before every page is.
export interface NavEntry {
	id: string;
	label: string;
}

export const docsNav: NavEntry[] = [
	{ id: 'index', label: 'Overview' },
	{ id: 'getting-started', label: 'Getting started' },
	{ id: 'menu-bar-app', label: 'The menu bar app' },
	{ id: 'protocol', label: 'The protocol' },
	{ id: 'engines', label: 'Engines and the measurement' },
	{ id: 'auth', label: 'Authentication' },
	{ id: 'control-api', label: 'The control API' },
	{ id: 'api/reference', label: 'API reference' },
	{ id: 'troubleshooting', label: 'Troubleshooting' },
];

// Pages that are not collection entries but always exist.
export const staticDocs = new Set(['api/reference']);

export const docsHref = (id: string) => (id === 'index' ? '/docs' : `/docs/${id}`);

export function neighbours(id: string, existing: Set<string>) {
	const i = docsNav.findIndex((e) => e.id === id);
	const prev = docsNav.slice(0, Math.max(i, 0)).reverse().find((e) => existing.has(e.id));
	const next = docsNav.slice(i + 1).find((e) => existing.has(e.id));
	return { prev, next };
}
