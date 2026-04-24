<?php
/**
 * Run a command with a portable timeout when coreutils timeout is unavailable.
 *
 * @package WP_Plugin_Base
 */

if ( PHP_SAPI !== 'cli' ) {
	fwrite( STDERR, "run_with_php_timeout.php must be executed from the command line.\n" );
	exit( 1 );
}

if ( $argc < 3 ) {
	fwrite( STDERR, "Usage: php run_with_php_timeout.php <timeout-seconds> <command> [args...]\n" );
	exit( 1 );
}

$timeout = (float) $argv[1];
$command = array_slice( $argv, 2 );

if ( $timeout <= 0 ) {
	fwrite( STDERR, "Timeout must be greater than zero seconds.\n" );
	exit( 1 );
}

$descriptors = array(
	0 => array( 'pipe', 'r' ),
	1 => array( 'pipe', 'w' ),
	2 => array( 'pipe', 'w' ),
);

$process = proc_open( $command, $descriptors, $pipes );
if ( ! is_resource( $process ) ) {
	fwrite( STDERR, "Unable to start command.\n" );
	exit( 1 );
}

fclose( $pipes[0] );
stream_set_blocking( $pipes[1], false );
stream_set_blocking( $pipes[2], false );

$stdout    = '';
$stderr    = '';
$started   = microtime( true );
$timed_out = false;
$exit_code = null;

while ( true ) {
	$status = proc_get_status( $process );
	$stdout .= stream_get_contents( $pipes[1] );
	$stderr .= stream_get_contents( $pipes[2] );

	if ( ! $status['running'] ) {
		if ( isset( $status['exitcode'] ) && $status['exitcode'] >= 0 ) {
			$exit_code = (int) $status['exitcode'];
		}
		break;
	}

	if ( ( microtime( true ) - $started ) >= $timeout ) {
		$timed_out = true;
		proc_terminate( $process );
		usleep( 250000 );

		$status = proc_get_status( $process );
		if ( $status['running'] ) {
			proc_terminate( $process, 9 );
		}
		break;
	}

	usleep( 100000 );
}

$stdout .= stream_get_contents( $pipes[1] );
$stderr .= stream_get_contents( $pipes[2] );
fclose( $pipes[1] );
fclose( $pipes[2] );

$close_code = proc_close( $process );
if ( null === $exit_code || -1 !== $close_code ) {
	$exit_code = $close_code;
}

fwrite( STDOUT, $stdout );
fwrite( STDERR, $stderr );

if ( $timed_out ) {
	fwrite( STDERR, "Command timed out after {$timeout}s.\n" );
	exit( 124 );
}

exit( (int) $exit_code );
