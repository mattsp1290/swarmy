import './styles.css';
import App from './App.svelte';
import { mount } from 'svelte';

const target = document.getElementById('app');

if (!target) {
  throw new Error('Unable to mount Swarmy web app: missing #app');
}

mount(App, { target });
