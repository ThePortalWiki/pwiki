<?php
 
if(! defined( 'MEDIAWIKI' ) ) {
   echo( "This is an extension to the MediaWiki package and cannot be run standalone.\n" );
   die( -1 );
}
 
define('EXTENSION_VERSION','R1');
 
$wgExtensionCredits['parserhook'][] = array(
  'name'         => 'SubString and StrLen',
  'author'       =>'Brian Malinconico', 
  'url'          => 'http://www.theaquariumwiki.com/User:PsiPro',
  'description'  => 'This extension adds a wraper for the php-substr function, and the strlen function.',
  'version'      => EXTENSION_VERSION
);
 
 
$wgExtensionFunctions[] = 'efSubStringParserFunction_Setup';
$wgHooks['LanguageGetMagic'][] = 'efSubStringParserFunction_Magic';
$wgHooks['LanguageGetMagic'][] = 'efStrLenParserFunction_Magic';
 
function efSubStringParserFunction_Setup() {
        global $wgParser;
 
        $wgParser->setFunctionHook( 'substring', 'efSubStringParserFunction_Render' );
        $wgParser->setFunctionHook( 'strlen', 'efStrLenParserFunction_Render' );
        return true;
}
 
function efSubStringParserFunction_Magic( &$magicWords, $langCode ) {
        $magicWords['substring'] = array( 0, 'substring' );
        return true;
}
 
function efSubStringParserFunction_Render( &$parser, $string = '', $start = 0, $length = '') {      
        if ($length == '')
                return substr($string,$start);
        else
                return substr($string,$start,$length);
}
 
function efStrLenParserFunction_Magic( &$magicWords, $langCode ) {
        $magicWords['strlen'] = array( 0, 'strlen' );
        return true;
}
 
function efStrLenParserFunction_Render( &$parser, $string = '') {           
        return strlen($string);
}
?>
