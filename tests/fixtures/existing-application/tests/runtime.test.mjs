import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

// This explicit compiled-entry smoke gate runs after compilation. It does not
// replace browser qualification against the real WordPress host globals.
test( 'compiled application imports its host globals without mounting on unrelated pages', () => {
	const context = {
		self: {},
		window: { ReactJSXRuntime: {} },
		document: { getElementById: () => null, currentScript: { tagName: 'SCRIPT', src: 'https://example.invalid/plugin/build/index.js' } },
		wp: { element: {}, components: {}, dataviews: {}, i18n: { __: ( value ) => value } },
	};
	context.self = context;
	context.window.wp = context.wp;
	vm.runInNewContext( fs.readFileSync( 'build/index.js', 'utf8' ), context, { timeout: 1000 } );
	assert.ok( fs.existsSync( 'build/index.asset.php' ) );
} );
