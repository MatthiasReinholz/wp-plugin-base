import './application.scss';
import { createRoot, useState } from '@wordpress/element';
import type { ComponentType } from 'react';
import { Button } from '@wordpress/components';
import { __ } from '@wordpress/i18n';

export function App() {
	const [ DataView, setDataView ] = useState< ComponentType | null >( null );
	const [ message, setMessage ] = useState( '' );
	return (
		<div className="existing-application">
			<Button
				variant="secondary"
				onClick={ async () => {
					try {
						const module = await import( './data-view' );
						setDataView( () => module.default );
					} catch {
						setMessage(
							__(
								'Unable to load the view. Please retry.',
								'existing-application'
							)
						);
					}
				} }
			>
				{ __( 'Load items', 'existing-application' ) }
			</Button>
			{ DataView && <DataView /> }
			<p role="status">{ message }</p>
		</div>
	);
}

const target = document.getElementById( 'existing-application-root' );
if ( target ) {
	createRoot( target ).render( <App /> );
}
