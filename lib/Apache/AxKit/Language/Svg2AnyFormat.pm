package Apache::AxKit::Language::Svg2AnyFormat;

@ISA = ( 'Apache::AxKit::Language' );

BEGIN {
   $Apache::AxKit::Language::Svg2AnyFormat::VERSION = 0.01
}

use Apache;
use Image::Magick;
use Apache::Request;
Apache::AxKit::Cache;
use File::Copy ();
use File::Temp ();
use File::Path ();
use Cwd;
use strict;

my $olddir;
my $tempdir;
my $cache;

my %Config = 
(  
    SVGOutputMimeType => "image/png"
);

my %MimeTypeSuffixMappings =
(
    "image/png"  => "png",
    "image/jpeg" => "jpg",
    "image/gif"  => "gif",
    "application/pdf"  => "pdf"
);

sub stylesheet_exists () { 0; }

sub handler
{
    my $class = shift;
    my ( $r, $xml_provider, undef, $last_in_chain ) = @_;
    
    my $mime;
    my $suffix = "png";
    
    print STDERR "CAME IN TO IT\n";
    
    if( ! $last_in_chain )
    {
        fail( "This is a Serializer, hence it has to be the last in the chain!" );
    }
    
    if( $r->pnotes( "axkit_mime_type" ) )
    {
        $mime = $r->pnotes( "axkit_mime_type" )
    }
    else
    {
        $mime = $r->dir_config( "SVGOutputMimeType" ) || $Config{SVGOutputMimeType};
    }
    
    
    if( ! exists $MimeTypeSuffixMappings{$mime} )
    {
        $mime   = $Config{SVGOutputMimeType};
        $suffix = "png";
    }
    else
    {
        $suffix = $MimeTypeSuffixMappings{$mime};
    }
    
    my $tempdir = File::Temp::tempdir();
    my $image = new Image::Magick();

    if ( ! $tempdir ) 
    {
        die "Cannot create tempdir: $!";
    }
    
    $olddir = cwd;
    
    if( my $dom = $r->pnotes('dom_tree') )
    {
        my $xmlstring = $dom->toString();
        delete $r->pnotes()->{'dom_tree'};
        
        my $fh = Apache->gensym();
        chdir( $tempdir ) || fail( "Cannot cd: $!" );
        open($fh, ">temp.svg") || fail( "Cannot write: $!" );
        print $fh $xmlstring;
        close( $fh ) || fail( "Cannot close: $!" );
    }
    elsif( my $xmlstring = $r->pnotes('xml_string') )
    {
        my $fh = Apache->gensym();
        chdir( $tempdir ) || fail( "Cannot cd: $!" );
        open($fh, ">temp.svg") || fail( "Cannot write: $!" );
        print $fh $xmlstring;
        close( $fh ) || fail( "Cannot close: $!" );
    }
    else
    {
        my $text = eval { ${$xml_provider->get_strref()} };
        
        if ( $@ ) 
        {
            my $fh = $xml_provider->get_fh();
            chdir($tempdir) || fail("Cannot cd: $!");
            File::Copy::copy($fh, "temp.svg");
        }
        else 
        {
            my $fh = Apache->gensym();
            chdir($tempdir) || fail( "Cannot cd: $!" );
            open($fh, ">temp.svg") || fail( "Cannot write: $!" );
            print $fh $text;
            close($fh) || fail("Cannot close: $!");
        }
    }
    
    chdir( $tempdir ) || fail("Cannot cd: $!");
    
    my $retval = $image->Read( "temp.svg" );
    $image->Write( "temp.$suffix" );
    
    $AxKit::Cfg->AllowOutputCharset(0);
    
    my $pdfh = Apache->gensym();
    
    open( $pdfh, "<temp.$suffix" ) or fail( "Could not open $mime: $!" );
    $r->content_type($mime);
    local $/;
    
    $r->print(<$pdfh>);
    
    return Apache::Constants::OK;
}

sub cleanup {
    chdir $olddir;
    File::Path::rmtree($tempdir);
}

sub fail {
    cleanup();
    die @_;
}

1;


__END__

=pod

=head1 NAME

Apache::AxKit::Language::Svg2AnyFormat - SVG Serializer

=head1 SYNOPSIS

  AddHandler axkit .svg

  ## Fairly important to cache the output because
  ## transformation is highly CPU-Time and Memory consuming
  AxCacheDir /tmp/axkit_cache

  ## When using SvgCgiSerialize this is vital 
  ## because the cgi-parameters are not used
  ## by default to build the cache
  AxAddPlugin Apache::AxKit::Plugin::QueryStringCache

  <Files ~ *.svg>
    AxAddStyleMap application/svg2anyformat Apache::AxKit::Language::Svg2AnyFormat
    AxAddProcessor application/svg2anyformat NULL

    ## optional with this variable you can
    ## overwrite the default output format 
    ## PNG
    ## Supported Values:
    ##    image/jpeg
    ##    image/png
    ##    image/gif
    ##    application/pdf
    PerlSetVar SVGOutputMimeType image/jpeg
  
    ## optional module to pass the format using cgi-parameters
    ## to the module. For supported values see above
    ## and the man-page of the plugin
    AxAddPlugin Apache::AxKit::Plugin::SvgCgiSerialize   
  </Files>

=head1 DESCRIPTION

Svg2AnyFormat is a serializer which can transform SVG to many different
output formats(e.g. png, jpg, ... ). At the moment it uses Image::Magick as conversion library
which does not support the whole set of svg features. In one case the conversion
could work in another not. You have to give it a try. Please note because 
Svg2AnyFormat to any format is a searializer it HAS TO BE LAST in the transformer 
chain!!!!

=head1 VERSION

0.01

=head1 SEE ALSO

L<Apache::AxKit::Plugin::SvgCgiSerialize>

=head1 AUTHOR

Tom Schindl <tom.schindl@bestsolution.at>

=cut
