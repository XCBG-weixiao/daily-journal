import {cache} from 'react';
import {snapshot} from './repository';
export const loadSnapshot=cache(()=>snapshot());
