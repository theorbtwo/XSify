package ExtUtils::XSify::VarDecl;
use 5.10.0;
use Moose;
use MooseX::StrictConstructor;
use Try::Tiny;

extends 'ExtUtils::XSify::Symbol';

sub return_type {
  my ($self) = @_;

  my $type = $self->cursor->getCursorType;
  ExtUtils::XSify::Type->new(type => $type);
}

sub make_xs {
  my ($self) = @_;

  return if $self->unsupported;

  my $module = $self->perl_module;

  my ($return_type_c, $retval_eq, $output_section);
  if ($self->return_type) {
    $return_type_c = $self->return_type->output_name;
    $retval_eq = 'RETVAL = ';
    $output_section = " OUTPUT:\n  RETVAL";
  } else {
    $return_type_c = 'void';
    $retval_eq = '';
    $output_section = "";
  }

  my $short_c_name = $self->short_c_name;

  return <<END;
MODULE = $module  PACKAGE = $module

$return_type_c
$short_c_name()
 CODE:
  $retval_eq $short_c_name;
$output_section

END
}

sub more_to_do {
  my ($self) = @_;

  return if $self->unsupported;

  $self->return_type;
}

"variables don't";
