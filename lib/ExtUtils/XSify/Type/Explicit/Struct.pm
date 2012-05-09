package ExtUtils::XSify::Type::Explicit::Struct;
use Moose;

extends 'ExtUtils::XSify::Type::Explicit::Record';

sub output_name {
  my ($self) = @_;
  
  my $name = $self->cursor->getCursorSpelling;
  
  return 'struct '.$name;
}

'Takes a kickin and keeps on lickin';
