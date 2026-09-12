// The API reference's data shape, and the reading order of the routes.
// src/lib/openapi.ts reads docs/openapi.yaml at build time and renders every
// route from the YAML; this table contributes the group order, the group
// blurbs, and a fallback summary for anything the YAML has not got yet —
// which, since CI validates the daemon against the YAML, should be nothing.

export type Method = 'GET' | 'POST' | 'PATCH' | 'WS';

export interface Field {
	name: string;
	type: string;
	required?: boolean;
	note: string;
}

export interface Endpoint {
	method: Method;
	path: string;
	summary: string;
	description?: string;
	request?: Field[];
	response?: string; // example JSON
	responseTypes?: string[]; // content types the YAML lists for the 2xx
	responseFields?: Field[]; // from the YAML schema
	responseNote?: string;
	errors?: { code: string; when: string }[];
	ws?: string; // the same command as a WebSocket frame
	pinned?: boolean; // rendered from docs/openapi.yaml
	planned?: boolean; // only this table names it so far
}

export interface Group {
	id: string;
	label: string;
	blurb?: string;
	endpoints: Endpoint[];
}

export interface EventKind {
	type: string;
	when: string;
	example: string;
	pinned?: boolean;
	planned?: boolean;
}

export interface ApiSpec {
	source: 'openapi' | 'merged' | 'spec';
	version?: string;
	groups: Group[];
	events: EventKind[];
	pinned?: number;
	planned?: number;
}

export const specTable: ApiSpec = {
	source: 'spec',
	groups: [
		{
			id: 'discovery',
			label: 'Discovery',
			blurb: 'The one call a client makes first.',
			endpoints: [
				{
					method: 'GET',
					path: '/',
					summary: 'Who this is, how to authenticate, where the sockets are.',
					response: `{ "name": "Sonocles", "version": "0.1.2", "auth": "bearer",
  "ports": { "http": 7357, "ws": 7358 } }`,
				},
			],
		},
		{
			id: 'stream',
			label: 'The stream',
			blurb:
				'The same frames on both transports, both live at once. A consumer can attach before capture starts and stay attached across stops.',
			endpoints: [
				{
					method: 'GET',
					path: '/events',
					summary: 'The stream, as server-sent events.',
				},
				{
					method: 'WS',
					path: 'ws://127.0.0.1:7358',
					summary: 'The stream, as WebSocket messages.',
				},
			],
		},
		{
			id: 'control',
			label: 'Control',
			blurb:
				'Start and stop capture, and choose the engine, without touching the popover. Start, stop and status answer the same Status object; the engine routes answer the Engine one.',
			endpoints: [
				{ method: 'GET', path: '/status', summary: 'What the sidecar is doing.' },
				{ method: 'POST', path: '/start', summary: 'Begin capture.' },
				{ method: 'POST', path: '/stop', summary: 'End capture.' },
				{ method: 'GET', path: '/engine', summary: 'The engine, and which ones this Mac can run.' },
				{ method: 'POST', path: '/engine', summary: 'Switch engine.' },
			],
		},
		{
			id: 'token',
			label: 'The token',
			blurb: 'Rotation is the whole management surface. There is nothing to create, list or delete.',
			endpoints: [
				{ method: 'POST', path: '/token/rotate', summary: 'Issue a new token; the old one is dead.' },
			],
		},
	],
	events: [
		{
			type: 'partial',
			when: 'A volatile hypothesis, revised as you speak.',
			example: '{ "type": "partial", "text": "the menu bar", "seq": 3, "audioEnd": 40.8, "lagMs": 200 }',
		},
		{
			type: 'final',
			when: 'Settled text for one utterance.',
			example: '{ "type": "final", "text": "the menu bar app is listening", "seq": 9, "audioEnd": 42.12 }',
		},
		{
			type: 'engine',
			when: 'The engine changed.',
			example: '{ "event": "engine", "engine": "fluid320", "label": "Parakeet 320 ms" }',
		},
	],
};
