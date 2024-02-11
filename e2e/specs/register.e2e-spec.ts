import { test, expect } from '@playwright/test';
import { db } from '../test-utils';

test.describe('Registration', () => {
  test.beforeAll(async () => {
    await db.reset();
  });

  test.afterAll(async () => {
    await db.teardown();
  });

  test('admin registration', async ({ page }) => {
    // welcome
    await page.goto('/');
    await page.getByRole('button', { name: 'Getting Started' }).click();

    // register
    await expect(page).toHaveTitle(/Admin Registration/);
    await page.getByLabel('Admin Email').fill('admin@immich.app');
    await page.getByLabel('Admin Password', { exact: true }).fill('password');
    await page.getByLabel('Confirm Admin Password').fill('password');
    await page.getByLabel('Name').fill('Immich Admin');
    await page.getByRole('button', { name: 'Sign up' }).click();

    // login
    await expect(page).toHaveTitle(/Login/);
    await page.goto('/auth/login');
    await page.getByLabel('Email').fill('admin@immich.app');
    await page.getByLabel('Password').fill('password');
    await page.getByRole('button', { name: 'Login' }).click();

    // onboarding
    await expect(page).toHaveURL(/\/auth\/onboarding$/);
    await page.getByRole('button', { name: 'Theme' }).click();
    await page.getByRole('button', { name: 'Storage Template' }).click();
    await page.getByRole('button', { name: 'Done' }).click();

    // success
    await expect(page).toHaveURL(/\/photos/);
  });
});
