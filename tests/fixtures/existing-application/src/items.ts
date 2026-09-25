export type Item = { id: string; name: string };

export const items: Item[] = [
	{ id: 'alpha', name: 'Alpha' },
	{ id: 'beta', name: 'Beta' },
];

export function findItem( id: string ): Item | undefined {
	return items.find( ( item ) => item.id === id );
}
