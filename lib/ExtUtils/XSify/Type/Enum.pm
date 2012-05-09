package ExtUtils::XSify::Type::Enum;
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
  
  return 'enum '.$name;
}

'Four shalt thou not count, neither count thou two, excepting that thou then proceed to three. Five is right out.';
