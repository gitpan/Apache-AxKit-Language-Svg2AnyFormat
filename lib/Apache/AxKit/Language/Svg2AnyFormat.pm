package Apache::AxKit::Language::Svg2AnyFormat;

@ISA = ( 'Apache::AxKit::Language' );

BEGIN {
   $Apache::AxKit::Language::Svg2AnyFormat::VERSION = 0.02
}

use Apache;
# use Image::Magick;
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
    SVGOutputMimeType   => "image/png",
    SVGOutputSerializer => "ImageMagick",
    SVGOutputLibRSVGBin => "/usr/local/bin"
);

my %MimeTypeSuffixMappings =
(
    "image/png"              => "png",
    "image/jpeg"             => "jpg",
    "image/gif"              => "gif",
    "application/pdf"        => "pdf",
    "application/postscript" => "eps"
);

my %MimeTypeLibRSVGFormatMappings =
(
    "image/png"        => "png",
## DOES NOT WORK CORRECTLY AT THE MOMENT
## ONE CAN TURN ON BY COMMENTING IN
##    "image/jpeg"       => "jpeg"
);

sub stylesheet_exists () { 0; }

sub handler
{
    my $class = shift;
    my ( $r, $xml_provider, undef, $last_in_chain ) = @_;
    
    my $mime;
    my $suffix = "png";
    my $serializer;
    my $rsvg_bin;
    
    AxKit::Debug(8, "Transform started!!!!");
    
    print STDERR "IN HERE!!!!!!\n";
    
    if( ! $last_in_chain )
    {
        fail( "This is a Serializer, hence it has to be the last in the chain!" );
    }
    
    if( $r->pnotes( "axkit_mime_type" ) )
    {
        AxKit::Debug(8, "MimeType retrieved from Plugin");
        $mime = $r->pnotes( "axkit_mime_type" );
    }
    else
    {
        AxKit::Debug(8, "MimeType retrieved from CONF or using Default");
        $mime = $r->dir_config( "SVGOutputMimeType" ) || $Config{SVGOutputMimeType};
    }
    
    AxKit::Debug(8, "MimeType is set to '$mime'");
    
    if( ! exists $MimeTypeSuffixMappings{$mime} )
    {
        AxKit::Debug(8, "MimeType is not known. We are using DEFAULTS");
        $mime   = $Config{SVGOutputMimeType};
        $suffix = "png";
    }
    else
    {
        AxKit::Debug(8, "Setting suffix. To mapped value");
        $suffix = $MimeTypeSuffixMappings{$mime};
    }

    $serializer = $r->dir_config( "SVGOutputSerializer" ) || $Config{SVGOutputSerializer};
    $rsvg_bin   = $r->dir_config( "SVGOutputLibRSVGBin" ) || $Config{SVGOutputLibRSVGBin};
    
    if( $serializer eq "ImageMagick" || ! exists $MimeTypeLibRSVGFormatMappings{$mime} ) 
    {
        AxKit::Debug(8, "We need Image-Magick because ImageMagick should be used as serializer or LibRSVG could not create desired format");
        
        ## Loading at runtime
        require Image::Magick;
    }
    elsif( $serializer eq "LibRSVG" )
    {
        AxKit::Debug(8, "LibRSVG is registered as serializer");
        
        ## nothing to be loaded because we are using command line
    }
    else
    {
        fail( "This is an unknown serializer for me." );
    }
    
    my $tempdir = File::Temp::tempdir();
    
    AxKit::Debug(8, "Got tempdir: $tempdir");
    
    if ( ! $tempdir ) 
    {
        die "Cannot create tempdir: $!";
    }
    
    $olddir = cwd;
    
    if( my $dom = $r->pnotes('dom_tree') )
    {
        AxKit::Debug(8, "Got a dom tree");
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
        AxKit::Debug(8, "Got a xml-string");
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
            AxKit::Debug(8, "No ref");
            my $fh = $xml_provider->get_fh();
            chdir($tempdir) || fail("Cannot cd: $!");
            File::Copy::copy($fh, "temp.svg");
        }
        else 
        {
            AxKit::Debug(8, "It has been a ref");
            
            my $fh = Apache->gensym();
            chdir($tempdir) || fail( "Cannot cd: $!" );
            open($fh, ">temp.svg") || fail( "Cannot write: $!" );
            print $fh $text;
            close($fh) || fail("Cannot close: $!");
        }
    }
    
    chdir( $tempdir ) || fail("Cannot cd: $!");
    
    my $retval;
    
    if( $serializer eq "ImageMagick" )
    {
        AxKit::Debug(8, "Serializer is ImageMagick");
        
        my $image = new Image::Magick();
        $retval = $image->Read( "temp.svg" );
        
        if( "$retval" )
        {
            fail( "ImageMagick failed. Reason: $retval" );
        }
        
        $image->Write( "temp.$suffix" );
    }
    else
    {
        AxKit::Debug(8, "Serializer is: LibRSVG");
        
        if( exists $MimeTypeLibRSVGFormatMappings{$mime} )
        {
            AxKit::Debug(8, "MimeType is supported by LibRSVG");
            
            $retval = system( "$rsvg_bin/rsvg -f ".$MimeTypeLibRSVGFormatMappings{$mime}." temp.svg temp.$suffix" );
    

            if( $retval )
            {
                fail( "rsvg exited with status code $retval" );
            }
        }
        else
        {
            AxKit::Debug(8, "MimeType '$mime' **NOT** is supported by LibRSVG");
            
            my $image = new Image::Magick();

            AxKit::Debug(8, "STEP 1: rsvg convert to PNG");
            
            $retval = system( "$rsvg_bin/rsvg -f png temp.svg temp.png" );
            
            if( $retval )
            {
                fail( "rsvg exited with status code $retval" );
            }
            
            AxKit::Debug(8, "STEP 2: ImageMagick to FINAL format '$mime'");

            chdir( $tempdir ) || fail("Cannot cd: $!");

            $retval = $image->Read( "temp.png" );
            
            if( "$retval" )
            {
                fail( "ImageMagick failed. Reason: $retval" );
            }
            
            $image->Write( "temp.$suffix" );
            
            if( "$retval" )
            {
                fail( "ImageMagick failed. Reason: $retval" );
            }
        }
    }

    AxKit::Debug(8, "Serialization finished.");

    $AxKit::Cfg->AllowOutputCharset(0);
    
    my $pdfh = Apache->gensym();
    
    open( $pdfh, "<temp.$suffix" ) or fail( "Could not open $mime: $!" );
    $r->content_type( $mime );
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

=head2 ImageMagick

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

=head2 LibRSVG

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
    ## Supported Values(Native Formats):
    ##    image/png
    ## If you specify any other format:
    ##   svg->png is done by LibRSVG
    ##   png->chosen format Image::Magick
    PerlSetVar SVGOutputMimeType image/jpeg
    
    PerlSetVar SVGOutputSerializer LibRSVG
    
    ## only to be set if path differs from
    ## /usr/local/bin
    PerlSetVar SVGOutputLibRSVGBin /usr/bin/rsvg
    
    ## optional module to pass the format using cgi-parameters
    ## to the module. For supported values see above
    ## and the man-page of the plugin
    AxAddPlugin Apache::AxKit::Plugin::SvgCgiSerialize   
  </Files>


=head1 DESCRIPTION

Svg2AnyFormat is a serializer which can transform SVG to many different
output formats(e.g. png, jpg, ... ). At the moment it uses Image::Magick or LibRSVG as conversion libraries
which do not support the whole set of svg features. In one case the conversion
could work in another not. You have to give it a try. Please note because 
Svg2AnyFormat to any format is a searializer it HAS TO BE LAST in the transformer 
chain!!!!

Please note when referencing external material (e.g. Images) you'll have to use an absolute path

=head2 Image::Magick

If no SVGOutputSerializer is set Image::Magick is used as default. The reason is simply
because of backward compatility. You could also set Image::Magick explicitly with

=head3 Example:

  PerlSetVar SVGOutputSerializer ImageMagick

=head3 Advantges:

=over

=item 

Nearly any format can be exported

=item 

known to work on many os

=back

=head3 Disadvantages:

=over

=item 

it's fairly big

=item 

it does not support as much of the SVG-Spec as LibRSVG

=back

=head2 LibRSVG

LibRSVG is part of the gnome project. And could also be used as SVG-Serializer at the moment
the only really supported output-format is PNG. As a matter of that if you want to use
LibRSVG as your SVG-Serializer and the output format is an other than PNG, LibRSVG is used to
transform the SVG to PNG and ImageMagick from PNG to the desired output format.
At the moment no working PERL-Module for LibRSVG exists so we are using the commandline utility
rsvg.

=head3 Example:

  PerlSetVar SVGOutputSerializer LibRSVG
  PerlSetVar SVGOutputLibRSVGBin /usr/bin/rsvg

=head3 Advantages

=over

=item 

supports more of SVG-spec than Image::Magick

=item

not that big

=back

=head3 Disadvantages:

=over

=item 

no Perl-Module for C-libary => command line used at the moment

=item

only PNG supported as output format. This is solved by using
Image::Magick in a second transformation step (LOW Performance!!!).

=back

=head1 VERSION

0.02

=head1 SEE ALSO

L<Apache::AxKit::Plugin::SvgCgiSerialize>

=head1 AUTHOR

Tom Schindl <tom.schindl@bestsolution.at>

=cut
