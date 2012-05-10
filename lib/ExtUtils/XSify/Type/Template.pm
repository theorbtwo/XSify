package ExtUtils::XSify::Type::Template;
use Moose;
use MooseX::StrictConstructor;

use ExtUtils::XSify::Type::Template::Class;

has 'template_cursor',
  is => 'ro',
  default => sub {
    my ($self) = @_;

    $self->template_ref->getCursorReferenced
  };

has 'template_ref',
  is => 'ro';

has 'num_parameters',
  is => 'ro',
  lazy => 1,
  default => sub {
    my ($self) = @_;

    my $n=0;

    $self->template_cursor->visitChildren(sub {
                                            $n++;
                                          });

    return $n;
  };

sub to_do_mark {
  return 'template:'.$_[0]->template_cursor->getCursorUSR;
}

sub instance {
  my ($self, $parameters) = @_;

  my $instance_kind = $self->template_cursor->getTemplateCursorKind;

  if ($instance_kind == 4) {
    # ClassDecl
    ExtUtils::XSify::Type::Template::Class->new(template => $self,
                                                parameters => $parameters);
  } else {
    die "Instance kind: $instance_kind";
  }
}

# Do not include the <...>; the caller will add those if it wants them.
sub output_name {
  my ($self) = @_;

  return $self->template_cursor->getCursorSpelling;
}

'fat_joke<yo_momma>';
