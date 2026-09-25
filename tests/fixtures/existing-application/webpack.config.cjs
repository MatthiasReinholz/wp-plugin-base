const path = require( 'node:path' );
const fs = require( 'node:fs' );
const base = require( '@wordpress/scripts/config/webpack.config' );
const { RawSource } = require( 'webpack' ).sources;

// Collect notices for modules actually bundled, including concatenated modules.
// Extracted WordPress and React globals are supplied by the host instead.
class ApplicationLicensesPlugin {
	apply( compiler ) {
		compiler.hooks.thisCompilation.tap( 'ApplicationLicenses', ( compilation ) => {
			compilation.hooks.processAssets.tap(
				{ name: 'ApplicationLicenses', stage: compiler.webpack.Compilation.PROCESS_ASSETS_STAGE_ADDITIONAL },
				() => {
					const packages = new Map();
					const visit = ( module ) => {
						if ( module.modules ) {
							for ( const nested of module.modules ) { visit( nested ); }
						}
						if ( ! module.resource || ! module.resource.includes( `${ path.sep }node_modules${ path.sep }` ) ) { return; }
						let directory = path.dirname( module.resource.split( '?' )[ 0 ] );
						while ( directory !== path.dirname( directory ) && ! fs.existsSync( path.join( directory, 'package.json' ) ) ) {
							directory = path.dirname( directory );
						}
						const metadata = JSON.parse( fs.readFileSync( path.join( directory, 'package.json' ), 'utf8' ) );
						const identity = `${ metadata.name }@${ metadata.version }`;
						if ( packages.has( identity ) ) { return; }
						const licenses = fs.readdirSync( directory ).filter( ( name ) => /^licen[cs]e(?:\.|$)/i.test( name ) && fs.statSync( path.join( directory, name ) ).isFile() );
						if ( ! licenses.length && metadata.repository?.url === 'git://github.com/blakeembrey/change-case.git' && metadata.license === 'MIT' ) {
							// Some published sibling packages omit the monorepo's shared license.
							packages.set( identity, fs.readFileSync( require.resolve( 'change-case/LICENSE' ), 'utf8' ) );
							return;
						}
						if ( ! licenses.length ) { throw new Error( `Missing bundled license: ${ identity }` ); }
						packages.set( identity, licenses.sort().map( ( name ) => fs.readFileSync( path.join( directory, name ), 'utf8' ) ).join( '\n' ) );
					};
					for ( const module of compilation.modules ) { visit( module ); }
					const notices = [ fs.readFileSync( path.join( __dirname, 'LICENSE' ), 'utf8' ),
						...[ ...packages ].sort().map( ( [ identity, license ] ) => `${ identity }\n${ license }` ) ];
					compilation.emitAsset( 'licenses.txt', new RawSource( notices.join( '\n\n' ) ) );
				}
			);
		} );
	}
}

module.exports = {
	...base,
	entry: { index: path.join( __dirname, 'src/index.tsx' ) },
	output: { ...base.output, path: path.join( __dirname, 'build' ), chunkFilename: '[name].[contenthash].js', publicPath: 'auto' },
	plugins: [ ...base.plugins, new ApplicationLicensesPlugin() ],
};
