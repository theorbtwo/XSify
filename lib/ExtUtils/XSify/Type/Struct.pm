package ExtUtils::XSify::Type::Struct;
use Moose;

extends 'ExtUtils::XSify::Type::Record';

has 'location', is => 'ro';
has 'parent_cursor', is => 'ro';

sub output_name {
  my ($self) = @_;
  
  my $name = $self->type->getTypeDeclaration->getCursorSpelling;
  
  return 'struct '.$name;
}

'Takes a kickin and keeps on lickin';
