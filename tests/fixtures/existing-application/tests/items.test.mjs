import assert from 'node:assert/strict';
import test from 'node:test';
import { findItem } from '../src/items.ts';

test( 'application lookup distinguishes known and unknown items', () => {
	assert.equal( findItem( 'alpha' ).name, 'Alpha' );
	assert.equal( findItem( 'missing' ), undefined );
} );
