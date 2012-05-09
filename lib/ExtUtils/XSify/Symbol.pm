package ExtUtils::XSify::Symbol;
use 5.10.0;
use warnings;
use strict;
use Moose;
use MooseX::StrictConstructor;
use Try::Tiny;

has 'cursor',
  is => 'ro',
  isa => 'CLang::Cursor',
  required => 1,
  ;

sub location {
  my ($self) = @_;

  my $loc = $self->cursor->getCursorLocation;
  my $presumed_filename = $loc->getPresumedLocationFilename;
  my $presumed_line = $loc->getPresumedLocationLine;

  return "$presumed_filename:$presumed_line";
}

sub unsupported {
  my ($self) = @_;

  # Variables which are inside namespaces that are really templates.
  # return from Try::Tiny's catch clause doesn't dwim.
  my $ret1;

  try {
    $self->cpp_namespace;
  } catch {
    die "Booggle?" if not defined $_;
    if ($_ =~ m/unsupported/i) {
      $ret1++;
    } else {
      die $_;
    }
  };
  return 1 if $ret1;

  # Variables whose return type is a template type:
  return 1 if $self->cursor->getCursorType->getTypeKind == 1;

  return 0;
}

sub short_c_name {
  my ($self) = @_;

  # The name to call this function from C, excluding any namespaces, names of enclosing classes, argument types, and template parameters.

  my $name = $self->cursor->getCursorSpelling;

  1 while ($name =~ s/<.*?>//);

  return $name;
}

sub perl_module {
  my ($self) = @_;

  my $namespace = $self->cpp_namespace;

  if (not $namespace) {
    return "OpenCV";
  } else {
    return "OpenCV::$namespace";
  }

  die "perl_module for function with namespace '$namespace'";
}

sub cpp_namespace {
  my ($self) = @_;

  my $namespace = '';
  my $cursor = $self->cursor;

  while ($cursor = $cursor->getCursorSemanticParent) {
    my $spelling = $cursor->getCursorSpelling."";
    last if $spelling eq '';
    my $display_name = $cursor->getCursorDisplayName;

    die "Unsupported: Can't cope with templates yet: $display_name" if("$display_name" ne "$spelling");
    if ($namespace) {
      $namespace = $spelling."::".$namespace;
    } else {
      $namespace = $spelling;
    }
  }

  return $namespace;
}

sub extended_name {
  my ($self) = @_;

  my $en = $self->cursor->getCursorUSR;
  $en =~ s/([^A-Za-z0-9])/sprintf "_%02x", ord $1/ge;

  return $en;
}

sub to_do_mark {
  my ($self) = @_;

  $self->cursor->getCursorUSR;
}

sub factory {
  my ($self, %args) = @_;
  my ($cursor) = $args{cursor};

  my $kind = $cursor->getCursorKind;

  my $kinds = {
               8 => 'Function',
               9 => 'Var',
               21 => 'Method',
               24 => 'Constructor',
               25 => 'Destructor',
               26 => 'Conversion',
              };

  my $class = $kinds->{$kind} or die "Don't know what to do with a cursor kind $kind in Symbol";
  $class = "ExtUtils::XSify::Symbol::$class";
  #Class::MOP::load_class($class);
  eval "use $class; 1" or die "$@";

  $class->new(%args);
}

'Formerly known as Prince';
