package ExtUtils::XSify::Type::Typedef;
use Moose;
use MooseX::StrictConstructor;
use ExtUtils::XSify::TypedefDecl;

has 'type',
  is => 'ro',
  required => 1,
  isa => 'CLang::Type'
  ;

has 'location', is => 'ro';
has 'parent_cursor', is => 'ro';

sub output_name {
  my ($self) = @_;

  my $name = $self->type->getTypeDeclaration->getCursorSpelling;

  return $name;
}

sub to_do_mark {
  my ($self) = @_;

  return $self->type->getTypeDeclaration->getCursorUSR;
}

sub more_to_do {
  my ($self) = @_;

  ExtUtils::XSify::TypedefDecl->new(cursor => $self->type->getTypeDeclaration);
}

sub make_xs {
}

'Dracula, Dracul, Drac or just D. Depends how well you know him.';
