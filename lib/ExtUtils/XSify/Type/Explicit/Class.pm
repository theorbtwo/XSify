package ExtUtils::XSify::Type::Explicit::Class;
use Moose;

extends 'ExtUtils::XSify::Type::Explicit::Record';

sub output_name {
  my ($self) = @_;
  
  my $name = $self->cursor->getCursorSpelling;
  
  return $name;
}

sub initial_access {
  'private';
}

'FactoryFactoryFactoryFactoryFactoryClassAdaptor';
