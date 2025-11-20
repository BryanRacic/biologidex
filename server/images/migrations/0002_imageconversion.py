# Generated manually for BiologiDex image conversion feature

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('images', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='ImageConversion',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('original_image', models.ImageField(help_text='Original uploaded image file', upload_to='conversions/originals/%Y/%m/%d/')),
                ('converted_image', models.ImageField(help_text='Converted dex-compatible image (PNG, max 2560x2560)', upload_to='conversions/processed/%Y/%m/%d/')),
                ('original_format', models.CharField(help_text='Original file format (JPEG, PNG, etc.)', max_length=10)),
                ('original_size', models.JSONField(help_text='Original dimensions as [width, height]')),
                ('converted_size', models.JSONField(help_text='Converted dimensions as [width, height]')),
                ('transformations', models.JSONField(blank=True, default=dict, help_text='Transformations applied during conversion (rotation, crop, etc.)')),
                ('checksum', models.CharField(db_index=True, help_text='SHA256 checksum of converted image', max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('expires_at', models.DateTimeField(help_text='Expiration time for automatic cleanup (30 minutes from creation)')),
                ('used_in_job', models.BooleanField(default=False, help_text='Whether this conversion has been used to create a vision job')),
                ('user', models.ForeignKey(help_text='User who uploaded this image for conversion', on_delete=django.db.models.deletion.CASCADE, related_name='image_conversions', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'verbose_name': 'Image Conversion',
                'verbose_name_plural': 'Image Conversions',
                'db_table': 'image_conversions',
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='imageconversion',
            index=models.Index(fields=['user', 'created_at'], name='image_conve_user_id_a64fbc_idx'),
        ),
        migrations.AddIndex(
            model_name='imageconversion',
            index=models.Index(fields=['expires_at'], name='image_conve_expires_1d9542_idx'),
        ),
        migrations.AddIndex(
            model_name='imageconversion',
            index=models.Index(fields=['checksum'], name='image_conve_checksu_5f8c42_idx'),
        ),
        migrations.AddIndex(
            model_name='imageconversion',
            index=models.Index(fields=['used_in_job'], name='image_conve_used_in_9e2f73_idx'),
        ),
    ]
