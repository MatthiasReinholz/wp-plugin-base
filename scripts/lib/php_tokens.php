<?php // phpcs:disable WordPress.Files.FileName.NotHyphenatedLowercase -- Shared tooling follows the existing scripts/lib naming convention.
/**
 * Shared PHP token primitives for static endpoint policy checks.
 *
 * @package WPPluginBase
 */

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
 * Resolves lexical function imports to targets for unqualified identifier tokens.
 *
 * Imports reset at each namespace declaration. Class imports, closure captures,
 * variable callbacks and runtime-generated names are deliberately not inferred.
 *
 * @param array $tokens PHP tokens.
 * @return array<int,string> Imported targets indexed by identifier token position.
 */
function wp_plugin_base_function_alias_targets( array $tokens ) {
	$aliases = array();
	$targets = array();
	$count   = count( $tokens );
	for ( $index = 0; $index < $count; $index++ ) {
		$id = wp_plugin_base_token_id( $tokens[ $index ] );
		if ( T_NAMESPACE === $id ) {
			$aliases = array();
		}
		if ( T_USE === $id ) {
			$declaration = '';
			for ( $next = $index + 1; $next < $count; $next++ ) {
				$text = wp_plugin_base_token_text( $tokens[ $next ] );
				if ( '(' === $text || ';' === $text ) {
					break;
				}
				$declaration .= wp_plugin_base_is_trivia_token( $tokens[ $next ] ) ? ' ' : $text;
			}
			if ( $next < $count && ';' === wp_plugin_base_token_text( $tokens[ $next ] ) ) {
				$aliases = array_merge( $aliases, wp_plugin_base_parse_function_imports( $declaration ) );
			}
		}
		if ( T_STRING === $id ) {
			$name = strtolower( wp_plugin_base_token_text( $tokens[ $index ] ) );
			if ( isset( $aliases[ $name ] ) ) {
				$targets[ $index ] = $aliases[ $name ];
			}
		}
	}
	return $targets;
}

/**
 * Parses a direct, grouped, or mixed PHP use declaration's function imports.
 *
 * @param string $declaration Text after use and before its semicolon.
 * @return array<string,string> Alias names mapped to fully qualified targets.
 */
function wp_plugin_base_parse_function_imports( $declaration ) {
	$declaration   = trim( $declaration );
	$all_functions = (bool) preg_match( '/^function\s+/i', $declaration );
	$declaration   = preg_replace( '/^function\s+/i', '', $declaration );
	$prefix        = '';
	$group         = strpos( $declaration, '{' );
	$aliases       = array();
	if ( false !== $group ) {
		$prefix      = trim( substr( $declaration, 0, $group ) );
		$declaration = trim( substr( $declaration, $group + 1 ), " \t\r\n}" );
	}
	foreach ( explode( ',', $declaration ) as $import ) {
		$import = trim( $import );
		if ( ! $all_functions && ! preg_match( '/^function\s+/i', $import ) ) {
			continue;
		}
		$import = preg_replace( '/^function\s+/i', '', $import );
		if ( ! preg_match( '/^([\\\\a-z_\x80-\xff][\\\\a-z0-9_\x80-\xff]*)(?:\s+as\s+([a-z_\x80-\xff][a-z0-9_\x80-\xff]*))?$/i', $import, $match ) ) {
			continue;
		}
		$target                          = ltrim( $prefix . $match[1], '\\' );
		$segments                        = explode( '\\', $target );
		$alias                           = isset( $match[2] ) ? $match[2] : end( $segments );
		$aliases[ strtolower( $alias ) ] = $target;
	}
	return $aliases;
}

/**
 * Matches a global function identifier or its lexical import, excluding methods.
 *
 * @param array             $tokens PHP tokens.
 * @param int               $index Identifier position.
 * @param string            $name Global function name.
 * @param array<int,string> $alias_targets Resolved import targets.
 * @return bool
 */
function wp_plugin_base_is_function_call_token( array $tokens, $index, $name, array $alias_targets ) {
	for ( $previous = $index - 1; $previous >= 0; $previous-- ) {
		if ( wp_plugin_base_is_trivia_token( $tokens[ $previous ] ) || '&' === wp_plugin_base_token_text( $tokens[ $previous ] ) ) {
			continue;
		}
		if ( in_array( strtolower( wp_plugin_base_token_text( $tokens[ $previous ] ) ), array( '->', '?->', '::', 'function', 'new' ), true ) ) {
			return false;
		}
		break;
	}
	if ( isset( $alias_targets[ $index ] ) ) {
		return 0 === strcasecmp( $alias_targets[ $index ], $name );
	}
	return wp_plugin_base_is_string_token( $tokens[ $index ], $name );
}
