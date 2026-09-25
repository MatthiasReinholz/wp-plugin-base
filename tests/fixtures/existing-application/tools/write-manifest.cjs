const crypto = require( 'node:crypto' );
const fs = require( 'node:fs' );
const path = require( 'node:path' );
const root = path.resolve( __dirname, '..' );
const files = fs.readdirSync( path.join( root, 'build' ), { recursive: true } )
	.filter( ( name ) => name !== 'manifest.json' && fs.statSync( path.join( root, 'build', name ) ).isFile() )
	.sort();
const artifacts = files.map( ( name ) => ( {
	path: `build/${ name }`,
	sha256: crypto.createHash( 'sha256' ).update( fs.readFileSync( path.join( root, 'build', name ) ) ).digest( 'hex' ),
} ) );
fs.writeFileSync( path.join( root, 'build/manifest.json' ), `${ JSON.stringify( { schema_version: 1, artifacts }, null, 2 ) }\n` );
