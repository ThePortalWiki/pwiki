<?php

if ( !defined( 'MEDIAWIKI' ) ) {
    die( 'Not a valid entry point.' );
}

class SubStringAndStrLenHooks {
    public static function onParserFirstCallInit( Parser $parser ) {
        $parser->setFunctionHook( 'substring', [ self::class, 'substring' ] );
        $parser->setFunctionHook( 'strlen', [ self::class, 'strlen' ] );
    }

    public static function substring( Parser $parser, $input = '', $start = 0, $length = null ) {
        $start = (int) $start;
        $length = is_null( $length ) ? null : (int) $length;

        return [ mb_substr( $input, $start, $length, 'UTF-8' ), 'noparse' => true, 'isHTML' => false ];
    }

    public static function strlen( Parser $parser, $input = '' ) {
        return [ mb_strlen( $input, 'UTF-8' ), 'noparse' => true, 'isHTML' => false ];
    }
}
