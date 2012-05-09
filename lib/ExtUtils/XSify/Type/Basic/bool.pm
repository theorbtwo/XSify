package ExtUtils::XSify::Type::Basic::bool;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'bool';
}

'bool';
