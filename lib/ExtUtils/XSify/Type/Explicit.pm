package ExtUtils::XSify::Type::Explicit;
use Moose;
use MooseX::StrictConstructor;

# This class represents types that require an explicit declaration -- struct foo, not *foo.
has 'cursor', is => 'ro';

sub to_do_mark {
  $_[0]->cursor->getCursorUSR;
}

sub location {
  my ($self) = @_;

  my $loc = $self->cursor->getCursorLocation;
  my $presumed_filename = $loc->getPresumedLocationFilename;
  my $presumed_line = $loc->getPresumedLocationLine;

  return "$presumed_filename:$presumed_line";
}

'I think, therefore I am.';
