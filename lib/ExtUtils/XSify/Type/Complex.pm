package ExtUtils::XSify::Type::Complex;
use Moose;
use MooseX::StrictConstructor;

has 'type',
  is => 'ro',
  required => 1,
  isa => 'CLang::Type'
  ;

sub output_name {
  my ($self) = @_;

  my $name = $self->type->getTypeDeclaration->getCursorSpelling;
  return "__complex__ $name";
}

"The square root of negitive WHAT?";
