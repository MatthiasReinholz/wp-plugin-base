<?php
/**
 * Token-based scanner for public WordPress endpoint authorization patterns.
 *
 * @package WPPluginBase
 */

if ( $argc < 2 ) {
	fwrite( STDERR, "Usage: php_wordpress_authorization_scanner.php <file>\n" );
	exit( 1 );
}

$file = $argv[1];
$code = file_get_contents( $file );
if ( false === $code ) {
	fwrite( STDERR, "Unable to read PHP file: {$file}\n" );
	exit( 1 );
}

$tokens = token_get_all( $code );

/**
 * Returns a token id, or null for single-character tokens.
 *
 * @param mixed $token Token.
 * @return int|null
 */
function wp_plugin_base_token_id( $token ) {
	return is_array( $token ) ? $token[0] : null;
}

/**
 * Returns token text.
 *
 * @param mixed $token Token.
 * @return string
 */
function wp_plugin_base_token_text( $token ) {
	return is_array( $token ) ? $token[1] : (string) $token;
}

/**
 * Returns a token line.
 *
 * @param mixed $token Token.
 * @return int
 */
function wp_plugin_base_token_line( $token ) {
	return is_array( $token ) ? (int) $token[2] : 1;
}

/**
 * Whether token is non-semantic trivia.
 *
 * @param mixed $token Token.
 * @return bool
 */
function wp_plugin_base_is_trivia_token( $token ) {
	$id = wp_plugin_base_token_id( $token );
	return in_array( $id, array( T_WHITESPACE, T_COMMENT, T_DOC_COMMENT ), true );
}

/**
 * Returns true when a token is a specific identifier.
 *
 * @param mixed  $token Token.
 * @param string $name Identifier.
 * @return bool
 */
function wp_plugin_base_is_string_token( $token, $name ) {
	if ( ! is_array( $token ) ) {
		return false;
	}

	if ( T_STRING === $token[0] ) {
		return 0 === strcasecmp( $token[1], $name );
	}

	if ( defined( 'T_NAME_FULLY_QUALIFIED' ) && T_NAME_FULLY_QUALIFIED === $token[0] ) {
		return 0 === strcasecmp( ltrim( $token[1], '\\' ), $name );
	}

	return false;
}

/**
 * Unquotes PHP string literals when possible.
 *
 * @param string $value Literal.
 * @return string
 */
function wp_plugin_base_unquote_php_string( $value ) {
	if ( strlen( $value ) < 2 ) {
		return $value;
	}

	$quote = $value[0];
	if ( ( "'" !== $quote && '"' !== $quote ) || substr( $value, -1 ) !== $quote ) {
		return $value;
	}

	return stripcslashes( substr( $value, 1, -1 ) );
}

/**
 * Normalizes tokens for simple true-return comparisons.
 *
 * @param array<int,mixed> $candidate_tokens Tokens.
 * @return string
 */
function wp_plugin_base_normalized_tokens( array $candidate_tokens ) {
	$normalized = '';
	foreach ( $candidate_tokens as $token ) {
		if ( wp_plugin_base_is_trivia_token( $token ) ) {
			continue;
		}
		$normalized .= strtolower( wp_plugin_base_token_text( $token ) );
	}

	return $normalized;
}

/**
 * Finds the matching closing delimiter for a token index.
 *
 * @param array<int,mixed> $tokens Tokens.
 * @param int              $start_index Start token index.
 * @param string           $open Open delimiter.
 * @param string           $close Close delimiter.
 * @return int|null
 */
function wp_plugin_base_find_matching_delimiter( array $tokens, $start_index, $open, $close ) {
	$depth = 0;
	$count = count( $tokens );

	for ( $i = $start_index; $i < $count; $i++ ) {
		$text = wp_plugin_base_token_text( $tokens[ $i ] );
		if ( $open === $text ) {
			$depth++;
			continue;
		}
		if ( $close === $text ) {
			$depth--;
			if ( 0 === $depth ) {
				return $i;
			}
		}
	}

	return null;
}

/**
 * Returns the next non-trivia token index.
 *
 * @param array<int,mixed> $tokens Tokens.
 * @param int              $start_index Start token index.
 * @param int|null         $end_index Optional end index.
 * @return int|null
 */
function wp_plugin_base_next_meaningful_index( array $tokens, $start_index, $end_index = null ) {
	$count = null === $end_index ? count( $tokens ) : min( count( $tokens ), $end_index + 1 );
	for ( $i = $start_index; $i < $count; $i++ ) {
		if ( ! wp_plugin_base_is_trivia_token( $tokens[ $i ] ) ) {
			return $i;
		}
	}

	return null;
}

/**
 * Splits function-call arguments at top-level commas.
 *
 * @param array<int,mixed> $argument_tokens Argument tokens without outer parentheses.
 * @return array<int,array<int,mixed>>
 */
function wp_plugin_base_split_top_level_arguments( array $argument_tokens ) {
	$arguments = array();
	$current   = array();
	$depth     = 0;

	foreach ( $argument_tokens as $token ) {
		$text = wp_plugin_base_token_text( $token );
		if ( ',' === $text && 0 === $depth ) {
			$arguments[] = $current;
			$current     = array();
			continue;
		}

		$current[] = $token;

		if ( in_array( $text, array( '(', '[', '{' ), true ) ) {
			$depth++;
		} elseif ( in_array( $text, array( ')', ']', '}' ), true ) && $depth > 0 ) {
			$depth--;
		}
	}

	if ( ! empty( $current ) ) {
		$arguments[] = $current;
	}

	return $arguments;
}

/**
 * Extracts a string literal from an argument token list.
 *
 * @param array<int,mixed> $argument_tokens Argument tokens.
 * @return string
 */
function wp_plugin_base_argument_string_literal( array $argument_tokens ) {
	foreach ( $argument_tokens as $token ) {
		if ( is_array( $token ) && T_CONSTANT_ENCAPSED_STRING === $token[0] ) {
			return wp_plugin_base_unquote_php_string( $token[1] );
		}
	}

	return '';
}

/**
 * Returns true when a token slice is exactly a true return body.
 *
 * @param array<int,mixed> $body_tokens Body tokens.
 * @return bool
 */
function wp_plugin_base_body_returns_true_only( array $body_tokens ) {
	$normalized = wp_plugin_base_normalized_tokens( $body_tokens );
	return in_array( $normalized, array( 'returntrue;', 'return(true);' ), true );
}

/**
 * Collects named functions/methods that only return true.
 *
 * @param array<int,mixed> $tokens Tokens.
 * @return array<string,bool>
 */
function wp_plugin_base_collect_true_callbacks( array $tokens ) {
	$callbacks = array();
	$count     = count( $tokens );

	for ( $i = 0; $i < $count; $i++ ) {
		if ( ! is_array( $tokens[ $i ] ) || T_FUNCTION !== $tokens[ $i ][0] ) {
			continue;
		}

		$name_index = wp_plugin_base_next_meaningful_index( $tokens, $i + 1 );
		if ( null === $name_index || ! is_array( $tokens[ $name_index ] ) || T_STRING !== $tokens[ $name_index ][0] ) {
			continue;
		}

		$open_paren = wp_plugin_base_next_meaningful_index( $tokens, $name_index + 1 );
		if ( null === $open_paren || '(' !== wp_plugin_base_token_text( $tokens[ $open_paren ] ) ) {
			continue;
		}

		$close_paren = wp_plugin_base_find_matching_delimiter( $tokens, $open_paren, '(', ')' );
		if ( null === $close_paren ) {
			continue;
		}

		$open_brace = wp_plugin_base_next_meaningful_index( $tokens, $close_paren + 1 );
		if ( null === $open_brace || '{' !== wp_plugin_base_token_text( $tokens[ $open_brace ] ) ) {
			continue;
		}

		$close_brace = wp_plugin_base_find_matching_delimiter( $tokens, $open_brace, '{', '}' );
		if ( null === $close_brace ) {
			continue;
		}

		$body = array_slice( $tokens, $open_brace + 1, $close_brace - $open_brace - 1 );
		if ( wp_plugin_base_body_returns_true_only( $body ) ) {
			$callbacks[ strtolower( $tokens[ $name_index ][1] ) ] = true;
		}
	}

	return $callbacks;
}

/**
 * Returns the inner entries of a PHP array literal.
 *
 * @param array<int,mixed> $array_tokens Array expression tokens.
 * @return array<int,array<int,mixed>>
 */
function wp_plugin_base_array_entries( array $array_tokens ) {
	$first = wp_plugin_base_next_meaningful_index( $array_tokens, 0 );
	if ( null === $first ) {
		return array();
	}

	$open_index = null;
	$open       = wp_plugin_base_token_text( $array_tokens[ $first ] );
	if ( '[' === $open ) {
		$open_index = $first;
		$close      = ']';
	} elseif ( is_array( $array_tokens[ $first ] ) && T_ARRAY === $array_tokens[ $first ][0] ) {
		$open_index = wp_plugin_base_next_meaningful_index( $array_tokens, $first + 1 );
		if ( null === $open_index || '(' !== wp_plugin_base_token_text( $array_tokens[ $open_index ] ) ) {
			return array();
		}
		$close = ')';
	} else {
		return array();
	}

	$close_index = wp_plugin_base_find_matching_delimiter( $array_tokens, $open_index, wp_plugin_base_token_text( $array_tokens[ $open_index ] ), $close );
	if ( null === $close_index ) {
		return array();
	}

	$inner = array_slice( $array_tokens, $open_index + 1, $close_index - $open_index - 1 );
	return wp_plugin_base_split_top_level_arguments( $inner );
}

/**
 * Extracts a top-level key/value pair from an array entry.
 *
 * @param array<int,mixed> $entry_tokens Array entry tokens.
 * @return array{key:string,value:array<int,mixed>}|null
 */
function wp_plugin_base_array_entry_key_value( array $entry_tokens ) {
	$key_index = wp_plugin_base_next_meaningful_index( $entry_tokens, 0 );
	if ( null === $key_index || ! is_array( $entry_tokens[ $key_index ] ) ) {
		return null;
	}

	$arrow = wp_plugin_base_next_meaningful_index( $entry_tokens, $key_index + 1 );
	if ( null === $arrow || ! is_array( $entry_tokens[ $arrow ] ) || T_DOUBLE_ARROW !== $entry_tokens[ $arrow ][0] ) {
		return null;
	}

	if ( T_CONSTANT_ENCAPSED_STRING === $entry_tokens[ $key_index ][0] ) {
		$key = wp_plugin_base_unquote_php_string( $entry_tokens[ $key_index ][1] );
	} elseif ( T_LNUMBER === $entry_tokens[ $key_index ][0] ) {
		$key = $entry_tokens[ $key_index ][1];
	} else {
		return null;
	}

	return array(
		'key'   => $key,
		'value' => array_slice( $entry_tokens, $arrow + 1 ),
	);
}

/**
 * Returns a top-level array value for a key.
 *
 * @param array<int,mixed> $array_tokens Array expression tokens.
 * @param string           $key Key.
 * @return array<int,mixed>|null
 */
function wp_plugin_base_array_top_level_value( array $array_tokens, $key ) {
	foreach ( wp_plugin_base_array_entries( $array_tokens ) as $entry ) {
		$key_value = wp_plugin_base_array_entry_key_value( $entry );
		if ( null !== $key_value && $key === $key_value['key'] ) {
			return $key_value['value'];
		}
	}

	return null;
}

/**
 * Whether an array expression has any top-level key from a list.
 *
 * @param array<int,mixed>  $array_tokens Array expression tokens.
 * @param array<int,string> $keys Keys.
 * @return bool
 */
function wp_plugin_base_array_has_top_level_key( array $array_tokens, array $keys ) {
	foreach ( wp_plugin_base_array_entries( $array_tokens ) as $entry ) {
		$key_value = wp_plugin_base_array_entry_key_value( $entry );
		if ( null !== $key_value && in_array( $key_value['key'], $keys, true ) ) {
			return true;
		}
	}

	return false;
}

/**
 * Returns REST endpoint option arrays from a register_rest_route third argument.
 *
 * @param array<int,mixed> $route_options_tokens Third argument tokens.
 * @return array<int,array<int,mixed>>
 */
function wp_plugin_base_route_option_slices( array $route_options_tokens ) {
	$endpoint_slices = array();
	$route_keys      = array( 'methods', 'callback', 'permission_callback' );

	foreach ( wp_plugin_base_array_entries( $route_options_tokens ) as $entry ) {
		$key_value        = wp_plugin_base_array_entry_key_value( $entry );
		$candidate_tokens = null === $key_value ? $entry : $key_value['value'];
		if ( null !== $key_value && ! ctype_digit( $key_value['key'] ) ) {
			continue;
		}

		if ( wp_plugin_base_array_has_top_level_key( $candidate_tokens, $route_keys ) ) {
			$endpoint_slices[] = $candidate_tokens;
		}
	}

	if ( ! empty( $endpoint_slices ) ) {
		return $endpoint_slices;
	}

	return array( $route_options_tokens );
}

/**
 * Finds literal strings in a token slice.
 *
 * @param array<int,mixed> $tokens Tokens.
 * @return array<int,string>
 */
function wp_plugin_base_string_literals_in_tokens( array $tokens ) {
	$literals = array();
	foreach ( $tokens as $token ) {
		if ( is_array( $token ) && T_CONSTANT_ENCAPSED_STRING === $token[0] ) {
			$literals[] = wp_plugin_base_unquote_php_string( $token[1] );
		}
	}

	return $literals;
}

/**
 * Whether a callback token slice is an intentional public callback.
 *
 * @param array<int,mixed>   $callback_tokens Callback value tokens.
 * @param array<string,bool> $true_callbacks Same-file callbacks that only return true.
 * @return bool
 */
function wp_plugin_base_callback_is_public_true( array $callback_tokens, array $true_callbacks ) {
	$first_index = wp_plugin_base_next_meaningful_index( $callback_tokens, 0 );
	if ( null === $first_index ) {
		return false;
	}

	$first = $callback_tokens[ $first_index ];
	if ( is_array( $first ) && T_CONSTANT_ENCAPSED_STRING === $first[0] ) {
		$value = wp_plugin_base_unquote_php_string( $first[1] );
		if ( '__return_true' === $value ) {
			return true;
		}
		if ( isset( $true_callbacks[ strtolower( $value ) ] ) ) {
			return true;
		}
	}

	foreach ( wp_plugin_base_string_literals_in_tokens( $callback_tokens ) as $literal ) {
		$parts = explode( '::', $literal );
		$name  = strtolower( end( $parts ) );
		if ( '__return_true' === $literal || isset( $true_callbacks[ $name ] ) ) {
			return true;
		}
	}

	$normalized = wp_plugin_base_normalized_tokens( $callback_tokens );
	if ( '__return_true' === $normalized || 'returntrue' === $normalized ) {
		return true;
	}

	for ( $i = 0; $i < count( $callback_tokens ); $i++ ) {
		if ( is_array( $callback_tokens[ $i ] ) && T_FN === $callback_tokens[ $i ][0] ) {
			for ( $j = $i + 1; $j < count( $callback_tokens ); $j++ ) {
				if ( is_array( $callback_tokens[ $j ] ) && T_DOUBLE_ARROW === $callback_tokens[ $j ][0] ) {
					$expression = array_slice( $callback_tokens, $j + 1 );
					$expr       = rtrim( wp_plugin_base_normalized_tokens( $expression ), ';' );
					return in_array( $expr, array( 'true', '(true)' ), true );
				}
			}
		}

		if ( is_array( $callback_tokens[ $i ] ) && T_FUNCTION === $callback_tokens[ $i ][0] ) {
			$open_brace = null;
			for ( $j = $i + 1; $j < count( $callback_tokens ); $j++ ) {
				if ( '{' === wp_plugin_base_token_text( $callback_tokens[ $j ] ) ) {
					$open_brace = $j;
					break;
				}
			}

			if ( null === $open_brace ) {
				continue;
			}

			$close_brace = wp_plugin_base_find_matching_delimiter( $callback_tokens, $open_brace, '{', '}' );
			if ( null === $close_brace ) {
				continue;
			}

			$body = array_slice( $callback_tokens, $open_brace + 1, $close_brace - $open_brace - 1 );
			if ( wp_plugin_base_body_returns_true_only( $body ) ) {
				return true;
			}
		}
	}

	return false;
}

/**
 * Emits a scanner finding.
 *
 * @param string $kind Kind.
 * @param int    $line Line.
 * @param string $identifier Identifier.
 * @param string $message Message.
 * @return void
 */
function wp_plugin_base_print_finding( $kind, $line, $identifier, $message ) {
	printf( "%s\t%d\t%s\t%s\n", $kind, $line, $identifier, $message );
}

$true_callbacks = wp_plugin_base_collect_true_callbacks( $tokens );
$count          = count( $tokens );

for ( $i = 0; $i < $count; $i++ ) {
	if ( ! wp_plugin_base_is_string_token( $tokens[ $i ], 'register_rest_route' ) ) {
		continue;
	}

	$open_paren = wp_plugin_base_next_meaningful_index( $tokens, $i + 1 );
	if ( null === $open_paren || '(' !== wp_plugin_base_token_text( $tokens[ $open_paren ] ) ) {
		continue;
	}

	$close_paren = wp_plugin_base_find_matching_delimiter( $tokens, $open_paren, '(', ')' );
	if ( null === $close_paren ) {
		continue;
	}

	$argument_tokens = array_slice( $tokens, $open_paren + 1, $close_paren - $open_paren - 1 );
	$arguments       = wp_plugin_base_split_top_level_arguments( $argument_tokens );
	$namespace       = isset( $arguments[0] ) ? wp_plugin_base_argument_string_literal( $arguments[0] ) : '';
	$route           = isset( $arguments[1] ) ? wp_plugin_base_argument_string_literal( $arguments[1] ) : '';
	$identifier      = ( '' !== $namespace && '' !== $route ) ? "{$namespace}:{$route}" : 'register_rest_route';
	$line            = wp_plugin_base_token_line( $tokens[ $i ] );

	if ( ! isset( $arguments[2] ) ) {
		wp_plugin_base_print_finding(
			'rest_permission_callback_missing',
			$line,
			$identifier,
			'Registering a REST route without permission_callback requires explicit security review.'
		);
		continue;
	}

	foreach ( wp_plugin_base_route_option_slices( $arguments[2] ) as $route_options ) {
		$callback_tokens = wp_plugin_base_array_top_level_value( $route_options, 'permission_callback' );

		if ( null === $callback_tokens ) {
			wp_plugin_base_print_finding(
				'rest_permission_callback_missing',
				$line,
				$identifier,
				'Registering a REST route without permission_callback requires explicit security review.'
			);
			continue;
		}

		if ( wp_plugin_base_callback_is_public_true( $callback_tokens, $true_callbacks ) ) {
			wp_plugin_base_print_finding(
				'rest_permission_callback_true',
				$line,
				$identifier,
				'Registering a REST route with an always-public permission_callback requires explicit security review.'
			);
		}
	}
}
