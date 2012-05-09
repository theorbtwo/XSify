package ExtUtils::XSify::Type::Class;
use Moose;

extends 'ExtUtils::XSify::Type::Record';

has 'location', is => 'ro';
has 'parent_cursor', is => 'ro';

sub output_name {
  my ($self) = @_;
  
  my $name = $self->type->getTypeDeclaration->getCursorSpelling;
  
  return $name;
}

sub initial_access {
  'private';
}

'FactoryFactoryFactoryFactoryFactoryClassAdaptor';
