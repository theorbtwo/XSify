package ExtUtils::XSify::Type::Explicit::Class;
use Moose;

extends 'ExtUtils::XSify::Type::Explicit::Record';

sub output_name {
  my ($self) = @_;
  
  my $name = $self->cursor->getCursorSpelling;
  if ($self->cpp_namespace) {
    $name = $self->cpp_namespace . '::' . $name;
  }
  my $location = $self->location;
  
  print "In class output_name, name=$name location=$location\n";
  
  return $name;
}

sub initial_access {
  'private';
}

'FactoryFactoryFactoryFactoryFactoryClassAdaptor';
