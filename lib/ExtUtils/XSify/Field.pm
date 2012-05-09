package ExtUtils::XSify::Field;
use Moose;
use MooseX::StrictConstructor;

has 'access', is => 'ro';
has 'cursor', is => 'ro';

has 'location',
  is => 'ro',
  lazy => 1,
  default => sub {
    my ($self) = @_;
    
    my $loc = $self->cursor->getCursorLocation;
    my $presumed_filename = $loc->getPresumedLocationFilename;
    my $presumed_line = $loc->getPresumedLocationLine;
    
    return "$presumed_filename:$presumed_line";
  };

sub to_do_mark {
  shift->cursor->getCursorUSR;
}

sub type {
  my ($self) = @_;

  ExtUtils::XSify::Type->new(type => $self->cursor->getCursorType,
                             parent_cursor => $self->cursor,
                             location => "type of ".$self->location);
}

sub more_to_do {
  my ($self) = @_;
  
  return $self->type;
}

sub make_xs {
  my ($self) = @_;

  my $type = $self->type->output_name;
  my $name = $self->cursor->getCursorSpelling;

  my $parent_type = "FIXME_PARENT_TYPE";

  my $text = <<END;
$type
$name($parent_type THIS)
 CODE:
  RETVAL = THIS.$name;
 OUTPUT:
  RETVAL
END
}

'just a little bit off the top';
