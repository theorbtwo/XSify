package ExtUtils::XSify::Symbol::Method;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Symbol::Function';

has 'access', is => 'ro';

'It is easier to destroy then to create';
