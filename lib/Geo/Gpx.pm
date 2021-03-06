unit role Geo::Gpx;

#use Carp;
#use DateTime::Format::ISO8601;
#use DateTime;
#use HTML::Entities qw( encode_entities encode_entities_numeric );
#use Scalar::Util qw( blessed );
#use Time::Local;
#use XML::Descent;

=begin pod
=encoding utf8

=head1 NAME

Geo::Gpx - Create and parse GPX files.

=head1 VERSION

This document describes Geo::Gpx version 0.27

=head1 SYNOPSIS

  # Version 0.10 compatibility
  use Geo::Gpx;
  my $gpx = Geo::Gpx->new( @waypoints );
  my $xml = $gpx->xml;

  # New API, generate GPX
  my $gpx = Geo::Gpx->new();
  $gpx->waypoints( \@wpt );
  my $xml = $gpx->xml( '1.0' );

  # Parse GPX
  my $gpx       = Geo::Gpx->new( xml => $xml );
  my $waypoints = $gpx->waypoints();
  my $tracks    = $gpx->tracks();

  # Parse GPX from open file
  my $gpx       = Geo::Gpx->new( input => $fh );
  my $waypoints = $gpx->waypoints();
  my $tracks    = $gpx->tracks();

=head1 DESCRIPTION

The original goal of this module was to produce GPX/XML files which were
parsable by both GPX Spinner and EasyGPS. As of version 0.13 it has
been extended to support general parsing and generation of GPX data. GPX
1.0 and 1.1 are supported.

=end pod

my $VERSION = '0.27';

# Values that are encoded as attributes
my %AS_ATTR = (
  wpt   => regex {^lat|lon$},
  rtept => regex {^lat|lon$},
  trkpt => regex {^lat|lon$},
  email => regex {^id|domain$},
  link  => regex {^href$}
);

my %KEY_ORDER = (
  wpt => <
     ele time magvar geoidheight name cmt desc src link sym type fix
     sat hdop vdop pdop ageofdgpsdata dgpsid extensions
  >,
);

# Map hash keys to GPX names
my %XMLMAP = (
  waypoints => %( waypoints => 'wpt' ),
  routes    => %(
    routes => 'rte',
    points => 'rtept'
  ),
  tracks => %(
    tracks   => 'trk',
    segments => 'trkseg',
    points   => 'trkpt'
  )
);

my @META;
my @ATTR;

BEGIN {
  @META = <name desc author copyright link time keywords>;
  @ATTR = <waypoints tracks routes version>;

  # Generate accessors
  for (@META, @ATTR).flat -> $attr {
#TODO    *{ __PACKAGE__ ~ '::' ~ $attr } = sub {
#TODO      my $self = shift;
#TODO      $self.{$attr} = shift if @_;
#TODO      return $self.{$attr};
#TODO    };
  }
}

method !parse-time($str) {
  my $dt = DateTime::Format::ISO8601.parse_datetime( $str );
#TODO  $!use-datetime ?? $dt !! $dt->epoch;
}

method !format-time($tm, $legacy) {
#TODO  unless blessed $tm && $tm.can( 'strftime' ) { # TODO
#TODO    return self!format-time(
#TODO      DateTime.from_epoch(
#TODO        epoch     => $tm,
#TODO        time_zone => 'UTC'
#TODO      ),
#TODO      $legacy
#TODO    );
#TODO  }
#TODO
#TODO  my $ts = $tm.strftime(
#TODO    $legacy
#TODO    ?? '%Y-%m-%dT%H:%M:%S.%7N%z'
#TODO    !! '%Y-%m-%dT%H:%M:%S%z'
#TODO  );
#TODO  $ts ~~ s/(\d{2})$/:$1/;
#TODO  return $ts;
}

# For backwards compatibility
method !init_legacy {
  @!keywords = <cache geocache groundspeak>;
  $!author   = %(
    name  => 'Groundspeak',
    email => %(
      id     => 'contact',
      domain => 'groundspeak.com'
    )
  );
  $!desc   = 'GPX file generated by Geo::Gpx';
  $!schema = <
     http://www.groundspeak.com/cache/1/0
     http://www.groundspeak.com/cache/1/0/cache.xsd
     >;

  require Geo::Cache; # TODO

  $!handler = %(
    create => sub {
    y  return Geo::Cache.new( @_ );
    },
    time => sub {
      return self!format-time( $_[0], 1 );
    },
  );
}

method !init_shiny_new($args) {
  $!use-datetime = $args<use_datetime> || 0;

  $!schema = @();

  $!handler = %(
    create => sub {
      return {@_};
    },
    time => sub {
      return self!format-time( $_[0], 0 );
    },
  );
}

=begin pod
=head1 INTERFACE

=head2 C<new( { args } )>

The original purpose of C<Geo::Gpx> was to allow an array of
L<Geo::Cache> objects to be converted into a GPX file. This behaviour is
maintained by this release:

  use Geo::Gpx;
  my $gpx = Geo::Gpx->new( @waypoints );
  my $xml = $gpx->xml;

New applications can use C <Geo::Gpx> to parse a GPX file :

 my $gpx = Geo::Gpx->new( xml => $gpx_document );

or from an open filehandle :

 my $gpx = Geo::Gpx->new( input => $fh );

or can create an empty container to which waypoints, routes and tracks
can then be added:

  my $gpx = Geo::Gpx->new();
  $gpx->waypoints( \@wpt );

The following additional options can be specified:

=over

=item C< use_datetime >

If true time values in parsed GPX will be L<DateTime> objects rather
than epoch times.

=back

=end pod

#sub new {
#  my ( $class, @args ) = @_;
#  my $self = bless( {}, $class );
#
#  # CORE::time because we have our own time method.
#  $self->{time} = CORE::time();
#
#  # Has to handle same calling convention as previous
#  # version.
#  if ( blessed $args[0] && $args[0]->isa( 'Geo::Cache' ) ) {
#    self!init_legacy();
#    $self->{waypoints} = \@args;
#  }
#  elsif ( @args % 2 == 0 ) {
#    my %args = @args;
#    self!init_shiny_new( \%args );
#
#    if ( exists $args{input} ) {
#      self!parse( $args{input} );
#    }
#    elsif ( exists $args{xml} ) {
#      self!parse( \$args{xml} );
#    }
#  }
#  else {
#    croak( "Invalid arguments" );
#  }
#
#  return $self;
#}

# Not a method
sub _trim($str) {
  $str ~~ s/^\s+//;
  $str ~~ s/\s+$//;
  $str ~~ s:g/\s+/ /;
  $str;
}

method !parse($source) {
  my $p = XML::Descent.new( { Input => $source } );

  $p.on(
    gpx => sub {
      my ( $elem, $attr ) = @_;

      $p.context;# ($self)

      my $version = $!version = ( $attr.{version} || '1.0' );

      my $parse-deep = sub {
        my ( $elem, $attr ) = @_;
        my $ob = $attr;    # Get attributes
        $p.context( $ob );
        $p.walk();
        return $ob;
      };

      # Parse a point
      my $parse_point = sub {
        my ( $elem, $attr ) = @_;
        my $pt = $parse-deep.( $elem, $attr );
        return %!handler<create>( %($pt) );
      };

      $p.on(
        '*' => sub {
          my ( $elem, $attr, $ctx ) = @_;
          $ctx.{$elem} = _trim( $p.text() );
        },
        time => sub {
          my ( $elem, $attr, $ctx ) = @_;
          my $tm = self!parse-time( _trim( $p.text() ) );
          $ctx.{$elem} = $tm if defined $tm;
        }
      );

      if ( _cmp_ver( $version, '1.1' ) >= 0 ) {

        # Handle 1.1 metadata
        $p.on(
          metadata => sub {
            $p.walk();
          },
          [ 'link', 'email', 'author' ] => sub {
            my ( $elem, $attr, $ctx ) = @_;
            $ctx.{$elem} = $parse-deep.( $elem, $attr );
          }
        );
      }
      else {

        # Handle 1.0 metadata
        $p.on(
          url => sub {
            my ( $elem, $attr, $ctx ) = @_;
            $ctx.{link}.{href} = _trim( $p.text() );
          },
          urlname => sub {
            my ( $elem, $attr, $ctx ) = @_;
            $ctx.{link}.{text} = _trim( $p.text() );
          },
          author => sub {
            my ( $elem, $attr, $ctx ) = @_;
            $ctx.{author}.{name} = _trim( $p.text() );
          },
          email => sub {
            my ( $elem, $attr, $ctx ) = @_;
            my $em = _trim( $p.text() );
            if ( $em ~~ m{^(.+)\@(.+)$} ) {
              $ctx.{author}.{email} = {
                id     => $1,
                domain => $2
              };
            }
          }
        );
      }

      $p.on(
        bounds => sub {
          my ( $elem, $attr, $ctx ) = @_;
          $ctx.{$elem} = $parse-deep.( $elem, $attr );
        },
        keywords => sub {
          my ( $elem, $attr ) = @_;
          @!keywords = 
            $p.text().split(',').map: { _trim(*) }
        },
        wpt => sub {
          my ( $elem, $attr ) = @_;
          @!waypoints.push: $parse_point.( $elem, $attr );
        },
        [ 'trkpt', 'rtept' ] => sub {
          my ( $elem, $attr, $ctx ) = @_;
          @!points.push: $parse_point.( $elem, $attr );
        },
        rte => sub {
          my ( $elem, $attr ) = @_;
          my $rt = $parse-deep.( $elem, $attr );
          @!routes.push: $rt;
        },
        trk => sub {
          my ( $elem, $attr ) = @_;
          my $tk = {};
          $p.context( $tk );
          $p.on(
            trkseg => sub {
              my ( $elem, $attr ) = @_;
              my $seg = $parse-deep.( $elem, $attr );
              @::($tk.segments).push: $seg;
            }
          );
          $p.walk();
          @!tracks.push: $tk;
        }
      );

      $p.walk();
    }
  );

  $p.walk();
}

=begin pod
=head2 C<add_waypoint( waypoint ... )>

Add one or more waypoints. Each waypoint must be a reference to a
hash. Each waypoint must include the keys C<lat> and C<lon> and may
include others:

  my $wpt = {
    lat         => 54.786989,
    lon         => -2.344214,
    ele         => 512,
    time        => 1164488503,
    magvar      => 0,
    geoidheight => 0,
    name        => 'My house & home',
    cmt         => 'Where I live',
    desc        => '<<Chez moi>>',
    src         => 'Testing',
    link        => {
      href => 'http://hexten.net/',
      text => 'Hexten',
      type => 'Blah'
    },
    sym           => 'pin',
    type          => 'unknown',
    fix           => 'dgps',
    sat           => 3,
    hdop          => 10,
    vdop          => 10,
    pdop          => 10,
    ageofdgpsdata => 45,
    dgpsid        => 247
  };

  $gpx.add_waypoint( $wpt );

Time values may either be an epoch offset or a L<DateTime>. If you wish
to specify the timezone use a L<DateTime>.

=end pod

method add_waypoint(*@args) {
  for @args -> $wpt {
#TODO    eval { keys %$wpt };
#TODO    croak "waypoint argument must be a hash reference"
#TODO     if $@;
#TODO
#TODO    croak "'lat' and 'lon' keys are mandatory in waypoint hash"
#TODO     unless exists $wpt.{lon} && exists $wpt.{lat};

    %!waypoints.push: $wpt;
  }
}

# Not a method
sub _iterate_points($pts) {
  unless defined $pts {
    sub { };
  }

  my $max = +@($pts);
  my $pos = 0;
  return sub {
    return if $pos >= $max;
    $pts.[ $pos++ ];
  };
}

# Not a method
sub _iterate_iterators(*@its) {
  return sub {
    loop {
      return Nil unless @its;
      my $next = @its[0].();
      return $next if defined $next;
      @its.shift;
    }
   }
}

=begin pod
=head2 C<iterate_waypoints()>

Get an iterator that visits all the waypoints in a C<Geo::Gpx>.

=end pod

method iterate_waypoints {
  _iterate_points( @!waypoints );
}

=begin pod
=head2 C<iterate_routepoints()>

Get an iterator that visits all the routepoints in a C<Geo::Gpx>.

=end pod

method iterate_routepoints {
  my @iter = ();
  if $!routes.exists {
    for @!routes -> $rte {
      @iter.append: _iterate_points( $rte<points> );
    }
  }

  _iterate_iterators( @iter );

}

=begin pod
=head2 C<iterate_trackpoints()>

Get an iterator that visits all the trackpoints in a C<Geo::Gpx>.

=end pod

method iterate_trackpoints {
  my @iter = ();
  if +@!tracks {
    for @!tracks -> $trk {
      if +$trk<segments> > 0 {
        for $trk<segments> -> $seg {
          @iter.append: _iterate_points( $seg<points> );
        }
      }
    }
  }

  _iterate_iterators( @iter );
}

=begin pod
=head2 C<iterate_points()>

Get an iterator that visits all the points in a C<Geo::Gpx>. For example

  my $iter = $gpx->iterate_points();
  while ( my $pt = $iter->() ) {
    print "Point: ", join( ', ', $pt->{lat}, $pt->{lon} ), "\n";
  }

=end pod

method iterate_points {
  _iterate_iterators(
    self.iterate_waypoints(),
    self.iterate_routepoints(),
    self.iterate_trackpoints()
  );
}

=begin pod
=head2 C<bounds( [ $iterator ] )>

Compute the bounding box of all the points in a C<Geo::Gpx> returning
the result as a hash reference. For example:

  my $gpx = Geo::Gpx->new( xml => $some_xml );
  my $bounds = $gpx->bounds();

returns a structure like this:

  $bounds = {
    minlat => 57.120939,
    minlon => -2.9839832,
    maxlat => 57.781729,
    maxlon => -1.230902
  };

C<$iterator> defaults to C<$self-E<gt>iterate_points>.

=end pod

method bounds($iter) {

  $iter ||= self.iterate_points;

  my $bounds = %();

  for $iter -> $pt {
    $bounds<minlat> = $!pt<lat> if ! $bounds<minlat>.defined || $!pt<lat> < $bounds<minlat>;
    $bounds<maxlat> = $!pt<lat> if ! $bounds<maxlat>.defined || $!pt<lat> > $bounds<maxlat>;
    $bounds<minlon> = $!pt<lon> if ! $bounds<minlon>.defined || $!pt<lon> < $bounds<minlon>;
    $bounds<maxlon> = $!pt<lon> if ! $bounds<maxlon>.defined || $!pt<lon> > $bounds<maxlon>;
  }

  $bounds;
}

sub _enc($arg) {
  encode_entities_numeric( $arg );
}

sub _tag($name, $attr, *@args ) {
  my @tag  = '<', $name;

  # Sort keys so the tests can depend on hash output order
  for %{$attr}.keys.sort -> $n {
    my $v = $attr{$n};
    @tag.append: ' ', $n, '="', _enc( $v ), '"';
  }

  if +@args {
    @tag.append: '>', @args.flat, '</', $name, ">\n";
  }
  else {
    @tag.push: " />\n";
  }

  join '', @tag;
}

method !xml($name, $value, $name_map = %()) {

  my $tag = $name_map.{$name} || $name;

  if $value.^can( 'xml' ) { # TODO
    # Handles legacy Gpx::Cache objects that can
    # render themselves. Note that Gpx::Cache->xml
    # adds the <wpt></wpt> wrapper - so this won't
    # work correctly for trkpt and rtept
    return $value.xml( $name );
  }
  elsif ( my $enc = %!encoder{$name} ).defined {
    return $enc.( $name, $value );
  }
  elsif $value ~~ Associative {
    my $attr    = {};
    my @cont    = ( "\n" );
    my $as_attr = %AS_ATTR{$name};

    # Shallow copy so we can delete keys as we output them
    my %v = %{$value};
    for (%KEY_ORDER{$name} || [], %v.keys.sort ).flat -> $k {
      if (my $vv = %v{$k}:delete).defined {
        if $as_attr.defined && $k ~~ $as_attr {
          $attr.{$k} = $vv;
        }
        else {
          @cont.push: self!xml( $k, $vv, $name_map );
        }
      }
    }

    _tag($tag, $attr, @cont);
  }
  elsif $value ~~ Positional {
    (@::($value).map: { self!xml( $tag, $_, $name_map ) }).join('');
  }
  else {
    _tag( $tag, %(), _enc($value) );
  }
}

sub _cmp_ver($v1, $v2) {
  my @v1 = split( '.', $v1 );
  my @v2 = split( '.', $v2 );

  while @v1 && @v2 {
    my $cmp = ( shift @v1 <=> shift @v2 );
    return $cmp if $cmp;
  }

  @v1 <=> @v2;
}

=begin pod
=head2 C<xml( [ $version ] )>

Generate GPX XML.

  my $gpx10 = $gpx->xml( '1.0' );
  my $gpx11 = $gpx->xml( '1.1' );

If the version is omitted it defaults to the value of the C<version>
attribute. Parsing a GPX document sets the version. If the C<version>
attribute is unset defaults to 1.0.

C<Geo::Gpx> version 0.10 used L<Geo::Cache> to render each of the
points. L<Geo::Cache> generates a number of hardwired values to suit the
original application of that module which aren't appropriate for general
purpose GPX manipulation. Legacy mode is triggered by passing a list of
L<Geo::Cache> points to the constructor; this should probably be avoided
for new applications.

=end pod

method xml($version = $!version || '1.0') {

  my @ret = ();

  @ret.push: qq{<?xml version="1.0" encoding="utf-8"?>\n};

  %!encoder = %(
    time => sub ($n, $v) {
      return _tag( $n, %(), _enc( %!handler<time>.( $v ) ) );
    },
    keywords => sub ($n, $v) {
      return _tag( $n, %(), _enc( @($v).join(', ') ) );
     }
  );

  # Limit to the latest version we know about
  if _cmp_ver( $version, '1.1' ) >= 0 {
    $version = '1.1';
  }
  else {

    # Modify encoder
    %!encoder<link> = sub ($n, $v) {
      my @v = ();
      @v.push: self!xml( 'url',     $v<href> ) if $v<href>.exists;
      @v.push: self!xml( 'urlname', $v<text> ) if $v<text>.exists;
      return @v.join: '';
    };
    %!encoder<email> = sub ($n, $v) {
      if $v<id>.exists && $<vdomain>.exists {
        return _tag( 'email', %(),
          _enc( ($v<id>, $v<domain>).join('@') ) );
      }
      else {
        return '';
      }
    };
    $!encoder<author> = sub ($n, $v) {
      my @v = ();
      @v.push: _tag( 'author', %(), _enc( $v<name> ) ) if $v<name>.exists;
      @v.push: self!xml( 'email', $v<email> ) if $v<email>.exists;
      @v.join: '';
    };
  }

  # Turn version into path element
  ( my $vpath = $version ) ~~ s:g/\./\//;

  my $ns = "http://www.topografix.com/GPX/$vpath";
  my $schema = join( ' ', $ns, "$ns/gpx.xsd", @( $!schema ) );

  @ret.append: qq{<gpx xmlns:xsd="http://www.w3.org/2001/XMLSchema" },
               qq{xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" },
               qq{version="$version" creator="Geo::Gpx" },
               qq{xsi:schemaLocation="$schema" },
               qq{xmlns="$ns">\n};

  my @meta = ();

#TODO  for @META -> $fld {
#TODO    if $self->{$fld}.exists { # TODO
#TODO      push @meta.push self!xml( $fld, $self->{$fld} );
#TODO    }
#TODO  }

  my $bounds = self.bounds( self.iterate_points() );
  if %($bounds) {
    @meta.push: _tag( 'bounds', %(), $bounds );
  }

  # Version 1.1 nests metadata in a metadata tag
  if _cmp_ver( $version, '1.1' ) >= 0 {
    @ret.push: _tag( 'metadata', %(), "\n", @meta );
  }
  else {
    @ret.append: @meta.flat;
  }

#TODO  for %XMLMAP.keys.sort -> $k {
#TODO    if $self->{$k}.exists {
#TODO      @ret.push: self!xml( $k, $self->{$k}, $XMLMAP{$k} );
#TODO    }
#TODO  }

  @ret.push: qq{</gpx>\n};

  @ret.join: '';
}

=begin pod
=head2 C<TO_JSON>

For compatibility with L<JSON> modules. Converts this object to a hash
with keys that correspond to the above methods. Generated ala:

  my %json = map { $_ => $self->$_ }
   qw(name desc author keywords copyright
   time link waypoints tracks routes version );
  $json{bounds} = $self->bounds( $iter );

With one difference: the keys will only be set if they are defined.

=end pod

method TO_JSON {
  my %json;    #= map {$_ => $self->$_} ...
#TODO  for ( @META, @ATTR ).flat -> $key {
#TODO    my $val = $self->$key;
#TODO    $json{$key} = $val if defined $val;
#TODO  }
  if my $bounds = %!bounds {
    %json{bounds} = %!bounds;
  }
  %json;
}

#### Legacy methods from 0.10

=begin pod
=head2 C<gpx>

Synonym for C<xml()>. Provided for compatibility with version 0.10.

=end pod

method gpx(*@args) {
  self.xml( @args );
}

=begin pod
=head2 C<loc>

Provided for compatibility with version 0.10.

=end pod

method loc {
  my @ret  = ();
  @ret.push: qq{<?xml version="1.0" encoding="ISO-8859-1"?>\n};
  @ret.push: qq{<loc version="1.0" src="Groundspeak">\n};

  if +@!waypoints > 0 {
    for @!waypoints -> $wpt {
      @ret.push: $wpt.loc();
    }
  }

  @ret.push: qq{</loc>\n};

  @ret.join: '';
}

=begin pod
=head2 C<gpsdrive>

Provided for compatibility with version 0.10.

=end pod

method gpsdrive {
  my @ret  = ();

  if +@!waypoints> 0 {
    for @!waypoints -> $wpt {
      @ret.push: $wpt.gpsdrive();
    }
  }

  @ret.join: '';
}

=begin pod
=head2 C<name( [ $newname ] )>

Accessor for the <name> element of a GPX. To get the name:

  my $name = $gpx->name();

and to set it:

  $gpx->name( 'My big adventure' );

=head2 C<desc( [ $newdesc ] )>

Accessor for the <desc> element of a GPX. To get the the description:

  my $desc = $gpx->desc();

and to set it:

  $gpx->desc('Got lost, wandered around for ages, got cold, got hungry.');

=head2 C<author( [ $newauthor ] )>

Accessor for the author structure of a GPX. The author information is stored
in a hash that reflects the structure of a GPX 1.1 document:

  my $author = $gpx->author();
  $author = {
    link => {
      text => 'Hexten',
      href => 'http://hexten.net/'
    },
    email => {
      domain => 'hexten.net',
      id => 'andy'
    },
    name => 'Andy Armstrong'
  },

When setting the author data a similar structure must be supplied:

  $gpx->author({
    name => 'Me!'
  });

The bizarre encoding of email addresses as id and domain is a
feature of GPX.

=head2 C<time( [ $newtime ] )>

Accessor for the <time> element of a GPX. The time is converted to a
Unix epoch time when a GPX document is parsed unless the C<use_datetime>
option is specified in which case times will be represented as
L<DateTime> objects.

When setting the time you may supply either an epoch time or a
L<DateTime> object.

=head2 C<keywords( [ $newkeywords ] )>

Access for the <keywords> element of a GPX. Keywords are stored as an
array reference:

  $gpx->keywords(['bleak', 'cold', 'scary']);
  my $k = $gpx->keywords();
  print join(', ', @{$k}), "\n";

prints

  bleak, cold, scary

=head2 C<copyright( [ $newcopyright ] )>

Access for the <copyright> element of a GPX.

  $gpx->copyright('(c) You Know Who');
  print $gpx->copyright(), "\n";

prints

  You Know Who

=head2 C<link>

Accessor for the <link> element of a GPX. Links are stored in a hash
like this:

  $link = {
    'text' => 'Hexten',
    'href' => 'http://hexten.net/'
  };

For example:

  $gpx->link({ href => 'http://google.com/', text => 'Google' });

=head2 C<waypoints( [ $newwaypoints ] )>

Accessor for the waypoints array of a GPX. Each waypoint is a hash
(which may also be a L<Geo::Cache> instance in legacy mode):

  my $wpt = {
    # All standard GPX fields
    lat           => 54.786989,
    lon           => -2.344214,
    ele           => 512,
    time          => 1164488503,
    magvar        => 0,
    geoidheight   => 0,
    name          => 'My house & home',
    cmt           => 'Where I live',
    desc          => '<<Chez moi>>',
    src           => 'Testing',
    link          => {
      href => 'http://hexten.net/',
      text => 'Hexten',
      type => 'Blah'
    },
    sym           => 'pin',
    type          => 'unknown',
    fix           => 'dgps',
    sat           => 3,
    hdop          => 10,
    vdop          => 10,
    pdop          => 10,
    ageofdgpsdata => 45,
    dgpsid        => 247
  };

All fields apart from C<lat> and C<lon> are optional. See the GPX
specification for an explanation of the fields. The waypoints array is
an anonymous array of such points:

  $gpx->waypoints([ { lat => 57.0, lon => -2 },
                    { lat => 57.2, lon => -2.1 } ]);

=head2 C<routes( [ $newroutes ] )>

Accessor for the routes array. The routes array is an array of hashes
like this:

  my $routes = [
    {
      'name' => 'Route 1'
      'points' => [
        {
          'lat' => '54.3286193447719',
          'name' => 'WPT1',
          'lon' => '-2.38972155527137'
        },
        {
          'lat' => '54.6634365629388',
          'name' => 'WPT2',
          'lon' => '-2.55373552512617'
        },
        {
          'lat' => '54.7289259665049',
          'name' => 'WPT3',
          'lon' => '-3.05196861273443'
        }
      ],
    },
    {
      'name' => 'Route 2'
      'points' => [
        {
          'lat' => '54.4165154835049',
          'name' => 'WPT4',
          'lon' => '-2.56153453279676'
        },
        {
          'lat' => '54.6670126167344',
          'name' => 'WPT5',
          'lon' => '-2.69526089464403'
        }
      ],
    }
  ];

  $gpx->routes($routes);

Each of the points in a route may have any of the attributes that are
legal for a waypoint.

=head2 C<tracks( [ $newtracks ] )>

Accessor for the tracks array. The tracks array is an array of hashes
like this:

  my $tracks = [
    {
      'name' => 'Track 1',
      'segments' => [
        {
          'points' => [
            {
              'lat' => '54.5182217145253',
              'lon' => '-2.62191579018834'
            },
            {
              'lat' => '54.1507759448355',
              'lon' => '-3.05774931478646'
            },
            {
              'lat' => '54.6016296784874',
              'lon' => '-3.40418920968631'
            }
          ]
        },
        {
          'points' => [
            {
              'lat' => '54.6862790450185',
              'lon' => '-3.68760108982739'
            }
          ]
        }
      ]
    },
    {
      'name' => 'Track 2',
      'segments' => [
        {
          'points' => [
            {
              'lat' => '54.9927807628549',
              'lon' => '-4.04712811256436'
            },
            {
              'lat' => '55.1148395198045',
              'lon' => '-4.33623533555793'
            },
            {
              'lat' => '54.6214174046189',
              'lon' => '-4.26293674042878'
            },
            {
              'lat' => '55.0540816059084',
              'lon' => '-4.42261020671926'
            },
            {
              'lat' => '55.4451622411372',
              'lon' => '-4.32873765338'
            }
          ]
        }
      ]
    }
  ];

=head2 C<version( [ $newversion ] )>

Accessor for the schema version of a GPX document. Versions 1.0 and 1.1
are supported.

  print $gpx->version();

prints

  1.0

=head1 DIAGNOSTICS

=over

=item C<< Invalid arguments >>

Invalid arguments passed to C<new()>.

=item C<< Undefined accessor method: %s >>

The various accessor methods are implemented as an AUTOLOAD handler.
This error is thrown if an attempt is made to call an accessor other
than C<name>, C<desc>, C<author>, C<time>, C<keywords>, C<copyright>,
C<link>, C<waypoints>, C<tracks>, C<routes> or C<version>.

=back

=head1 DEPENDENCIES

L<DateTime::Format::ISO8601>,
L<DateTime>,
L<HTML::Entities>,
L<Scalar::Util>,
L<Time::Local>,
L<XML::Descent> and optionally L<Geo::Cache>

=head1 INCOMPATIBILITIES

None reported.

=head1 SEE ALSO

L<Geo::Cache>, L<JSON>

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-geo-gpx@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Originally by Rich Bowen C<< <rbowen@rcbowen.com> >>.

This version by Andy Armstrong  C<< <andy@hexten.net> >>.

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007-2009, Andy Armstrong C<< <andy@hexten.net> >>. All
rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR
INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR
THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER
SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

=end pod
