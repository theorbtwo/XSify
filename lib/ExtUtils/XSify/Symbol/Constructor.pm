package ExtUtils::XSify::Symbol::Constructor;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Symbol::Method';

has 'access', is => 'ro';

'new';
