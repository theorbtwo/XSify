package ExtUtils::XSify::Type::Basic::short;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  'short';
}

'short';
