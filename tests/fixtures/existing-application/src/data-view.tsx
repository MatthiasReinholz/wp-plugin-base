import '@wordpress/dataviews/build-style/style.css';
import { useState } from '@wordpress/element';
import { DataViews, filterSortAndPaginate } from '@wordpress/dataviews';
import type { Field, View } from '@wordpress/dataviews';
import { __ } from '@wordpress/i18n';
import { items, type Item } from './items';

const fields: Field< Item >[] = [
	{ id: 'name', label: __( 'Name', 'existing-application' ), type: 'text' },
];

export default function ApplicationDataView() {
	const [ view, setView ] = useState< View >( {
		type: 'table',
		fields: [ 'name' ],
		page: 1,
		perPage: 10,
	} );
	const result = filterSortAndPaginate( items, view, fields );
	return (
		<DataViews
			data={ result.data }
			fields={ fields }
			view={ view }
			onChangeView={ setView }
			paginationInfo={ result.paginationInfo }
			getItemId={ ( item ) => item.id }
			defaultLayouts={ { table: {} } }
		/>
	);
}
